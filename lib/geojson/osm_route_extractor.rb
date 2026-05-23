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

    def initialize(relation_id:)
      @relation_id = relation_id
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

    def fetch_stations_from_relation(allow_missing_ref: false)
      query = <<~QL.squish
        [out:json][timeout:90];
        relation(#{@relation_id});
        node(r:"stop");
        out;
      QL

      parse_station_elements(post_overpass(query), allow_missing_ref: allow_missing_ref)
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

    def parse_station_elements(response, allow_missing_ref: false)
      stations = {}

      response.fetch("elements", []).each do |element|
        next unless element["type"] == "node"

        tags = element["tags"] || {}
        name = tags["name:zh"].presence || tags["name"]
        ref = tags["ref"].presence

        next if ref.blank? && !allow_missing_ref
        next if ref.blank?

        next if stations.key?(ref)

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
          response = Net::HTTP.post_form(uri, "data" => query)

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
