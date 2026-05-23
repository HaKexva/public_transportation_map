# frozen_string_literal: true

require "json"

module Geojson
  class MetroLineBuilder
    def self.build!(line)
      new(line).build!
    end

    def initialize(line)
      @line = line
    end

    def build!
      route_features = []

      @line.relation_ids.each do |relation_id|
        ways = OsmRouteExtractor.new(relation_id: relation_id).fetch_way_elements
        next if ways.empty?

        OsmRouteExtractor.new(relation_id: relation_id).stitch_line_strings(ways).each_with_index do |coordinates, index|
          route_features << route_feature(coordinates, branch_index: index)
        end
      end

      raise "No track geometry for #{@line.slug}" if route_features.empty?

      stations = fetch_stations_for_line
      collection = {
        type: "FeatureCollection",
        name: "#{@line.network_name}#{@line.name}",
        properties: {
          source: "Track geometry from OpenStreetMap route relations #{@line.relation_ids.join(', ')}. © OpenStreetMap contributors, ODbL.",
          network: @line.network_name,
          ref: @line.ref,
          osm_relations: @line.relation_ids
        },
        features: route_features + station_features(stations)
      }

      path = output_dir.join("#{@line.slug}.geojson")
      FileUtils.mkdir_p(output_dir)
      File.write(path, JSON.pretty_generate(collection))

      puts "Wrote #{path} (#{route_features.length} route segments, #{stations.length} stations)"
    end

    private

    def output_dir
      Rails.root.join("public/geojson", @line.output_subdir)
    end

    def fetch_stations_for_line
      unless @line.system_id == "taipei_metro"
        return merge_stations(stations_from_relations, default_stations)
      end

      if @line.slug == "circular"
        return fetch_circular_stations
      end

      if @line.slug == "xiaobitan_branch"
        stations = stations_from_relations.presence ||
          OsmRouteExtractor.new(relation_id: @line.relation_ids.first).fetch_stations(ref_prefix: "G03")

        return stations.select { |station| station[:ref]&.end_with?("A") }
      end

      if @line.slug == "xinbeitou_branch"
        branch = stations_from_relations
        branch = branch.select { |station| station[:ref] == "R22A" } if branch.any?

        return branch if branch.any?

        return OsmRouteExtractor.new(relation_id: @line.relation_ids.first)
          .fetch_stations(ref_prefix: "R")
          .select { |station| station[:ref] == "R22A" }
      end

      stations = stations_from_relations
      stations = default_stations if stations.empty?

      if @line.relation_ids.length > 1
        stations = merge_stations(stations, default_stations)
      end

      if @line.slug == "songshan_xindian"
        return stations.reject { |station| station[:ref] == "G03A" }
      end

      if @line.slug == "tamsui_xinyi"
        return stations.reject { |station| station[:ref].in?(%w[R22A]) }
      end

      stations
    end

    def default_stations
      OsmRouteExtractor.new(relation_id: @line.relation_ids.first)
        .fetch_stations(ref_prefix: @line.station_ref_prefix, network: @line.osm_networks)
    end

    def fetch_circular_stations
      extractor = OsmRouteExtractor.new(relation_id: @line.relation_ids.first)
      stops = extractor.fetch_named_stops_from_relation

      stops.filter_map do |stop|
        ref = TaipeiMetroCatalog::CIRCULAR_STATION_REFS_BY_NAME[stop[:name]]
        next unless ref

        stop.merge(ref: ref)
      end.sort_by { |station| station_sort_key(station[:ref]) }
    end

    def stations_from_relations
      @line.relation_ids.flat_map do |relation_id|
        OsmRouteExtractor.new(relation_id: relation_id).fetch_stations_from_relation
      end.then { |stations| merge_stations([], stations) }
    end

    def merge_stations(existing, extra)
      by_ref = existing.index_by { |station| station[:ref] }
      by_name = existing.each_with_object({}) do |station, index|
        index[station[:name]] = station if station[:name].present?
      end

      extra.each do |station|
        if by_ref[station[:ref]]
          next
        end

        if station[:name].present? && by_name[station[:name]]
          by_ref.delete(by_name[station[:name]][:ref])
        end

        by_ref[station[:ref]] = station
        by_name[station[:name]] = station if station[:name].present?
      end

      by_ref.values.sort_by { |station| station_sort_key(station[:ref]) }
    end

    def station_sort_key(ref)
      prefix = ref[/\A[A-Z]+/] || ref
      numeric = ref[/\d+/]
      suffix = ref.sub(/\A#{Regexp.escape(prefix)}#{numeric}/, "")

      [ prefix, numeric.to_i, suffix ]
    end

    def route_feature(coordinates, branch_index: 0)
      name = @line.name
      name = "#{name} (#{branch_index + 1})" if @line.relation_ids.length > 1

      {
        type: "Feature",
        properties: {
          feature_type: "route",
          ref: @line.ref,
          name: name,
          name_en: @line.name_en,
          color: @line.color
        },
        geometry: {
          type: "LineString",
          coordinates: coordinates
        }
      }
    end

    def station_features(stations)
      stations.filter_map do |station|
        next if station[:name].blank?

        ref = TaipeiMetroCatalog::TRANSFER_STATION_REFS_BY_NAME[station[:name]] || station[:ref]

        {
          type: "Feature",
          properties: {
            feature_type: "station",
            ref: ref,
            name: station[:name],
            line: @line.name,
            color: @line.color
          },
          geometry: {
            type: "Point",
            coordinates: [ station[:lon], station[:lat] ]
          }
        }
      end
    end
  end
end
