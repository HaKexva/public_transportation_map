# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module Geojson
  class OsmRouteExtractor
    OVERPASS_URLS = [
      "https://overpass.kumi.systems/api/interpreter",
      "https://overpass-api.de/api/interpreter"
    ].freeze

    def self.fetch_way_elements(way_id)
      new(relation_id: nil).fetch_way_by_id(way_id)
    end

    def self.fetch_aerialway_stations_for_way(way_id, ref_prefix:, include_angle_stations: false)
      new(relation_id: nil).fetch_aerialway_stations_for_way(
        way_id,
        ref_prefix: ref_prefix,
        include_angle_stations: include_angle_stations
      )
    end

    def initialize(relation_id:)
      @relation_id = relation_id
    end

    def fetch_way_by_id(way_id)
      query = <<~QL.squish
        [out:json][timeout:90];
        way(#{way_id});
        out geom;
      QL

      post_overpass(query).fetch("elements", []).select { |element| element["type"] == "way" && element["geometry"] }
    end

    def fetch_aerialway_stations_for_way(way_id, ref_prefix:, include_angle_stations: false)
      query = <<~QL.squish
        [out:json][timeout:90];
        way(#{way_id});
        node(w);
        out;
      QL

      stations = []
      index = 1

      post_overpass(query).fetch("elements", []).each do |element|
        next unless element["type"] == "node"

        tags = element["tags"] || {}
        name = tags["name:zh"].presence || tags["name"]
        next if name.blank?

        next if tags["aerialway"] == "pylon" && !tags.key?("aerialway:station") && tags["public_transport"] != "station"

        if name.match?(/轉角|Angle Station/i)
          next unless include_angle_stations

          stations << {
            ref: tags["ref"].presence || format("%s-A%02d", ref_prefix, index),
            name: name,
            lon: element["lon"],
            lat: element["lat"],
            angle_station: true,
            passenger_service: false
          }
          index += 1
          next
        end

        station_tags = %w[station stop_position]
        is_station = tags["aerialway"] == "station" ||
          tags["public_transport"].in?(station_tags) ||
          tags["railway"] == "station" ||
          name.match?(/站|Station/i)

        next unless is_station

        ref = tags["ref"].presence || format("%s%02d", ref_prefix, index)
        index += 1

        stations << {
          ref: ref,
          name: name,
          lon: element["lon"],
          lat: element["lat"]
        }
      end

      stations
    end

    def fetch_way_elements
      query = <<~QL.squish
        [out:json][timeout:180];
        relation(#{@relation_id});
        way(r);
        out geom;
      QL

      response = post_overpass(query)
      response.fetch("elements", []).select { |element| element["type"] == "way" && element["geometry"] }
    end

    def stitch_line_string(ways)
      chains = stitch_line_strings(ways)
      raise "Could not stitch OSM ways into a line" if chains.empty?

      chains.max_by(&:length)
    end

    def stitch_line_strings(ways)
      unused = ways.dup
      chains = []

      until unused.empty?
        chain = { "geometry" => unused.shift.fetch("geometry") }

        loop do
          connected = connect_next_way!(chain, unused)
          break unless connected
        end

        coordinates = chain["geometry"].map { |point| [ point["lon"], point["lat"] ] }
        chains << coordinates if coordinates.length >= 2
      end

      chains
    end

    def fetch_stations(ref_prefix:, network: "臺北捷運")
      network_filter = network_filter_clause(network)

      query = <<~QL.squish
        [out:json][timeout:90];
        node["railway"="station"]#{network_filter}["ref"~"^#{ref_prefix}"];
        out;
      QL

      parse_station_elements(post_overpass(query))
    end

    def fetch_stations_by_network(networks)
      network_filter = network_filter_clause(networks)

      query = <<~QL.squish
        [out:json][timeout:90];
        node["railway"="station"]#{network_filter};
        out;
      QL

      parse_station_elements(post_overpass(query))
    end

    def fetch_stations_from_relation(allow_missing_ref: false, ref_prefix: nil)
      query = <<~QL.squish
        [out:json][timeout:90];
        relation(#{@relation_id});
        node(r);
        out;
      QL

      parse_station_elements(
        post_overpass(query),
        allow_missing_ref: allow_missing_ref,
        ref_prefix: ref_prefix
      )
    end

    def fetch_named_stops_from_relation
      query = <<~QL.squish
        [out:json][timeout:90];
        relation(#{@relation_id});
        node(r:"stop");
        out;
      QL

      post_overpass(query).fetch("elements", []).filter_map do |element|
        next unless element["type"] == "node"

        tags = element["tags"] || {}
        name = tags["name:zh"].presence || tags["name"]
        next if name.blank?

        {
          ref: tags["ref"],
          name: name,
          lon: element["lon"],
          lat: element["lat"]
        }
      end
    end

    def parse_station_elements(response, allow_missing_ref: false, ref_prefix: nil)
      stations = {}
      generated_index = 1

      response.fetch("elements", []).each do |element|
        next unless element["type"] == "node"

        tags = element["tags"] || {}
        name = tags["name:zh"].presence || tags["name"]
        ref = tags["ref"].presence

        if ref.blank?
          next unless allow_missing_ref && name.present? && ref_prefix.present?

          ref = format("%s%02d", ref_prefix, generated_index)
          generated_index += 1
        end

        next if ref.blank?
        next if stations.key?(ref)

        role = tags["public_transport"] || tags["railway"] || tags["aerialway"]
        next if allow_missing_ref && name.blank? && role != "stop"

        stations[ref] = {
          ref: ref,
          name: name,
          lon: element["lon"],
          lat: element["lat"]
        }
      end

      stations.values.sort_by { |station| station[:ref] }
    end

    def orient_coordinates!(coordinates, start_point:, end_point:)
      start_dist = distance(coordinates.first, start_point) + distance(coordinates.last, end_point)
      reverse_dist = distance(coordinates.first, end_point) + distance(coordinates.last, start_point)

      coordinates.reverse! if reverse_dist < start_dist
      coordinates
    end

    private

    def network_filter_clause(network)
      return "" if network.blank?

      case network
      when Array
        values = network.map { |entry| Regexp.escape(entry) }.join("|")
        %(["network"~"^(#{values})$"])
      else
        %(["network"="#{network}"])
      end
    end

    def post_overpass(query)
      last_error = nil

      OVERPASS_URLS.each do |base_url|
        3.times do |attempt|
          uri = URI(base_url)
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = uri.scheme == "https"
          http.open_timeout = 30
          http.read_timeout = 240
          response = http.post(uri.path, URI.encode_www_form("data" => query))

          return JSON.parse(response.body) if response.is_a?(Net::HTTPSuccess)

          last_error = "Overpass request failed (#{response.code}) at #{base_url}"
          sleep(2 * (attempt + 1)) if response.code.to_i == 429
        end
      end

      raise last_error || "Overpass request failed"
    end

    def connect_next_way!(chain, unused)
      chain_start, chain_end = endpoints(chain["geometry"])

      unused.each_with_index do |way, index|
        way_start, way_end = endpoints(way["geometry"])

        if near?(chain_end, way_start)
          chain["geometry"] = chain["geometry"] + way["geometry"][1..]
          unused.delete_at(index)
          return true
        elsif near?(chain_end, way_end)
          reversed = reverse_geometry(way["geometry"])
          chain["geometry"] = chain["geometry"] + reversed[1..]
          unused.delete_at(index)
          return true
        elsif near?(chain_start, way_end)
          chain["geometry"] = way["geometry"][...-1] + chain["geometry"]
          unused.delete_at(index)
          return true
        elsif near?(chain_start, way_start)
          reversed = reverse_geometry(way["geometry"])
          chain["geometry"] = reversed[...-1] + chain["geometry"]
          unused.delete_at(index)
          return true
        end
      end

      false
    end

    def endpoints(geometry)
      [ geometry.first.values_at("lat", "lon"), geometry.last.values_at("lat", "lon") ]
    end

    def reverse_geometry(geometry)
      geometry.reverse
    end

    def near?(point_a, point_b, tolerance: 1e-6)
      (point_a[0] - point_b[0]).abs < tolerance && (point_a[1] - point_b[1]).abs < tolerance
    end

    def distance(coordinate, point)
      lon, lat = coordinate
      point_lon, point_lat = point
      Math.hypot(lon - point_lon, lat - point_lat)
    end
  end
end
