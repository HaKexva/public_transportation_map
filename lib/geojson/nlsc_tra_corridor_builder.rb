# frozen_string_literal: true

require "json"
require "fileutils"

module Geojson
  # Build passenger-corridor polylines from NLSC TRA centerlines and ordered station waypoints.
  module NlscTraCorridorBuilder
    OUTPUT_DIR = Rails.root.join("lib/geojson/fallback_tracks/tra").freeze

    LOCAL_RADIUS_M = 3_000
    STATION_SNAP_M = 800
    DENSIFY_STEP_M = 50

    FALLBACK_SLUGS = %w[
      yilan_line south_link taidong_line jiji_line pingtung_line hualien_port_line
      taichung_port_line western_trunk_north
    ].freeze

    STATION_REFS_BY_SLUG = {
      "yilan_line" => MetroLineBuilder::YILAN_CORRIDOR_WAYPOINT_REFS,
      "south_link" => MetroLineBuilder::SOUTH_LINK_STATION_REFS,
      "taidong_line" => MetroLineBuilder::TAIDONG_STATION_REFS,
      "jiji_line" => MetroLineBuilder::JIJI_STATION_REFS,
      "pingtung_line" => MetroLineBuilder::PINGTUNG_STATION_REFS,
      "hualien_port_line" => MetroLineBuilder::HUALIEN_PORT_STATION_REFS,
      "taichung_port_line" => MetroLineBuilder::TAICHUNG_PORT_STATION_REFS,
      "western_trunk_north" => MetroLineBuilder::WESTERN_TRUNK_NORTH_STATION_REFS
    }.freeze

    # Skip south-yard spurs that dip below the passenger corridor near 富岡 / 新富.
    EXCLUDE_REGIONS_BY_SLUG = {
      "western_trunk_north" => [
        { min_lon: 121.055, max_lon: 121.092, min_lat: 24.920, max_lat: 24.935, shelf_lat: 24.931 }
      ]
    }.freeze

    def self.rebuild_all!(slugs: FALLBACK_SLUGS)
      MetroLineBuilder.reset_tra_station_cache!
      slugs.filter_map do |slug|
        station_refs = STATION_REFS_BY_SLUG.fetch(slug)
        rebuild_fallback!(slug, station_refs: station_refs)
        slug
      rescue StandardError => error
        warn "Skipped NLSC fallback #{slug}: #{error.message}"
        nil
      end
    end

    def self.rebuild_fallback!(slug, station_refs:, exclude_regions: nil)
      waypoints = station_waypoints_for_refs(station_refs)
      raise "missing station waypoints for #{slug}" if waypoints.length < 2

      exclude_regions = EXCLUDE_REGIONS_BY_SLUG.fetch(slug, []) if exclude_regions.nil?
      corridor = build_corridor(waypoints, exclude_regions: exclude_regions)
      raise "empty NLSC corridor for #{slug}" unless corridor&.length.to_i >= 2

      FileUtils.mkdir_p(OUTPUT_DIR)
      path = OUTPUT_DIR.join("#{slug}.json")
      File.write(path, JSON.pretty_generate(corridor))
      puts "Wrote #{path} (#{corridor.length} points)"
      corridor
    end

    def self.build_corridor(waypoints, line_strings: nil, exclude_regions: [])
      lines = line_strings || NlscRailwayCatalog.line_strings_for_dataset(:tra)
      return nil if waypoints.length < 2 || lines.empty?

      combined = []
      waypoints.each_cons(2) do |from, to|
        local_lines = local_line_strings(lines, from, to, exclude_regions: exclude_regions)
        segment = path_between(local_lines, from, to, exclude_regions: exclude_regions)
        raise "no NLSC path #{from[:ref]} -> #{to[:ref]}" unless segment&.length.to_i >= 2

        segment = TrackGeometry.densify_coordinates(segment, max_step_m: DENSIFY_STEP_M)
        if combined.empty?
          combined.concat(segment)
        else
          combined.concat(segment.drop(1))
        end
      end

      TrackGeometry.dedupe_coordinates(combined)
    end

    def self.station_waypoints_for_refs(refs)
      refs.filter_map do |ref|
        station = MetroLineBuilder.tra_station_by_ref[ref]
        next unless station

        {
          ref: ref,
          name: station[:name],
          lon: station[:lon],
          lat: station[:lat]
        }
      end
    end

    def self.local_line_strings(all_lines, from, to, exclude_regions:)
      buffer = LOCAL_RADIUS_M / 111_000.0
      min_lon = [ from[:lon], to[:lon] ].min - buffer
      max_lon = [ from[:lon], to[:lon] ].max + buffer
      min_lat = [ from[:lat], to[:lat] ].min - buffer
      max_lat = [ from[:lat], to[:lat] ].max + buffer

      all_lines.select do |line|
        next false if line.length < 2

        line.any? do |lon, lat|
          lon.between?(min_lon, max_lon) && lat.between?(min_lat, max_lat)
        end
      end
    end

    def self.path_between(line_strings, from, to, exclude_regions: [])
      return nil if line_strings.empty?

      network_path = shortest_path_on_network(
        from[:lon], from[:lat],
        to[:lon], to[:lat],
        line_strings,
        exclude_regions: exclude_regions
      )
      network_path ||= TrackGeometry.spur_path_via_line_network(
        snap_to_network(from[:lon], from[:lat], line_strings),
        to[:lon], to[:lat],
        line_strings
      )
      return nil unless network_path&.length.to_i >= 2

      oriented = orient_path_between(network_path, from, to)
      snap_path_endpoints!(oriented, from, to)
      return oriented if path_connects_stations?(oriented, from, to)

      retry_path = shortest_path_on_network(
        from[:lon], from[:lat],
        to[:lon], to[:lat],
        line_strings,
        exclude_regions: []
      )
      return nil unless retry_path&.length.to_i >= 2

      oriented = orient_path_between(retry_path, from, to)
      snap_path_endpoints!(oriented, from, to)
      return nil unless path_connects_stations?(oriented, from, to)

      oriented
    end

    def self.path_connects_stations?(path, from, to)
      TrackGeometry.planar_distance_meters(path.first[0], path.first[1], from[:lon], from[:lat]) <= STATION_SNAP_M &&
        TrackGeometry.planar_distance_meters(path.last[0], path.last[1], to[:lon], to[:lat]) <= STATION_SNAP_M
    end

    def self.shortest_path_on_network(from_lon, from_lat, to_lon, to_lat, line_strings, exclude_regions: [])
      graph = build_filtered_graph(line_strings, exclude_regions: exclude_regions)
      return nil if graph.empty?

      start = graph.keys.min_by do |vertex|
        TrackGeometry.planar_distance_meters(vertex[0], vertex[1], from_lon, from_lat)
      end
      finish = graph.keys.min_by do |vertex|
        TrackGeometry.planar_distance_meters(vertex[0], vertex[1], to_lon, to_lat)
      end
      return nil unless start && finish
      return [ start, finish ] if start == finish

      start_gap = TrackGeometry.planar_distance_meters(start[0], start[1], from_lon, from_lat)
      finish_gap = TrackGeometry.planar_distance_meters(finish[0], finish[1], to_lon, to_lat)
      return nil if start_gap > STATION_SNAP_M || finish_gap > STATION_SNAP_M

      distances = { start => 0.0 }
      previous = {}
      queue = [ start ]

      until queue.empty?
        node = queue.min_by { |vertex| distances[vertex] }
        queue.delete(node)
        break if node == finish

        graph.fetch(node, {}).each do |neighbor, edge_distance|
          candidate = distances[node] + edge_distance
          next if distances[neighbor] && candidate >= distances[neighbor]

          distances[neighbor] = candidate
          previous[neighbor] = node
          queue << neighbor unless queue.include?(neighbor)
        end
      end

      return nil unless distances.key?(finish)

      path = []
      node = finish
      while node
        path.unshift(node)
        node = previous[node]
      end

      path.length >= 2 ? TrackGeometry.dedupe_coordinates(path) : nil
    end

    def self.build_filtered_graph(line_strings, exclude_regions: [])
      registry = []
      graph = Hash.new { |hash, key| hash[key] = {} }

      line_strings.each do |coordinates|
        coordinates.each_cons(2) do |start, finish|
          mid_lon = (start[0] + finish[0]) / 2.0
          mid_lat = (start[1] + finish[1]) / 2.0
          next if exclude_regions.any? { |region| edge_in_exclude_region?(start, finish, region) }

          from = snap_vertex(start, registry)
          to = snap_vertex(finish, registry)
          next if TrackGeometry.same_coordinate?(from, to)

          distance = TrackGeometry.planar_distance_meters(from[0], from[1], to[0], to[1])
          graph[from][to] = distance
          graph[to][from] = distance
        end
      end

      graph
    end

    def self.snap_vertex(point, registry)
      registry.each do |existing|
        return existing if TrackGeometry.planar_distance_meters(
          point[0], point[1], existing[0], existing[1]
        ) <= TrackGeometry::SPUR_NETWORK_VERTEX_SNAP_M
      end

      registry << point
      point
    end

    def self.snap_to_network(lon, lat, line_strings)
      projected_lon, projected_lat, = TrackGeometry.nearest_on_line_strings(lon, lat, line_strings)
      [ projected_lon, projected_lat ]
    end

    def self.orient_path_between(path, from, to)
      oriented = path.dup
      head_gap = TrackGeometry.planar_distance_meters(oriented.first[0], oriented.first[1], from[:lon], from[:lat]) +
        TrackGeometry.planar_distance_meters(oriented.last[0], oriented.last[1], to[:lon], to[:lat])
      tail_gap = TrackGeometry.planar_distance_meters(oriented.first[0], oriented.first[1], to[:lon], to[:lat]) +
        TrackGeometry.planar_distance_meters(oriented.last[0], oriented.last[1], from[:lon], from[:lat])
      oriented.reverse! if tail_gap + 1 < head_gap
      oriented
    end

    def self.snap_path_endpoints!(path, from, to)
      if TrackGeometry.planar_distance_meters(path.first[0], path.first[1], from[:lon], from[:lat]) <= STATION_SNAP_M
        path[0] = [ from[:lon], from[:lat] ]
      end
      if TrackGeometry.planar_distance_meters(path.last[0], path.last[1], to[:lon], to[:lat]) <= STATION_SNAP_M
        path[-1] = [ to[:lon], to[:lat] ]
      end
    end

    def self.edge_in_exclude_region?(start, finish, region)
      mid_lon = (start[0] + finish[0]) / 2.0
      mid_lat = (start[1] + finish[1]) / 2.0
      return true if point_in_region?(mid_lon, mid_lat, region)

      shelf_lat = region[:shelf_lat]
      return false unless shelf_lat

      max_lat = [ start[1], finish[1] ].max
      max_lat < shelf_lat &&
        start[0].between?(region.fetch(:min_lon), region.fetch(:max_lon)) &&
        finish[0].between?(region.fetch(:min_lon), region.fetch(:max_lon))
    end

    def self.point_in_region?(lon, lat, region)
      lon >= region.fetch(:min_lon) && lon <= region.fetch(:max_lon) &&
        lat >= region.fetch(:min_lat) && lat <= region.fetch(:max_lat)
    end

    private_class_method :local_line_strings, :path_between, :shortest_path_on_network,
                         :build_filtered_graph, :snap_vertex, :snap_to_network,
                         :orient_path_between, :snap_path_endpoints!, :point_in_region?,
                         :edge_in_exclude_region?, :path_connects_stations?
  end
end
