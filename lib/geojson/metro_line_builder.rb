# frozen_string_literal: true

require "json"

module Geojson
  class MetroLineBuilder
    # North track: secured area only. South track: public (non-secured) boarding.
    # Sources: taoyuan-airport.com/skytrain, Wikipedia PMS.
    SKYTRAIN_TRACKS = [
      { way_id: 256726319, segment: "north", label: "北側", boarding_area: "secured" },
      { way_id: 256726320, segment: "south", label: "南側", boarding_area: "public" }
    ].freeze

    # OSM ways 256726319 / 256726320 (cached for offline rebuild).
    SKYTRAIN_TRACK_FALLBACKS = {
      256726319 => [
        [ 121.2334829, 25.0764197 ], [ 121.2341376, 25.0769213 ], [ 121.2355514, 25.078025 ],
        [ 121.236953, 25.0791275 ], [ 121.2371298, 25.0792503 ], [ 121.2372602, 25.0793392 ],
        [ 121.237366, 25.0794164 ], [ 121.2376055, 25.0796065 ], [ 121.2382094, 25.080096 ]
      ],
      256726320 => [
        [ 121.23823, 25.0799459 ], [ 121.2376645, 25.0795237 ], [ 121.2375054, 25.0794155 ],
        [ 121.2373074, 25.0793067 ], [ 121.237077, 25.0791573 ], [ 121.2369536, 25.0790837 ],
        [ 121.2367405, 25.078917 ], [ 121.2350374, 25.0775732 ], [ 121.2343394, 25.0770225 ],
        [ 121.2342736, 25.0769559 ], [ 121.2341881, 25.0768637 ], [ 121.2341136, 25.0767812 ],
        [ 121.2339994, 25.0766704 ], [ 121.2335548, 25.0763378 ]
      ]
    }.freeze

    SKYTRAIN_BOARDING_STATIONS = [
      {
        ref: "ST1N",
        name: "第一航廈（北側）",
        name_en: "Terminal 1 (North)",
        terminal: "T1",
        track: "north",
        lon: 121.2380095,
        lat: 25.0798462,
        note: "管制區內 · 2F A/B 區（近 A7、B6 登機門）"
      },
      {
        ref: "ST2N",
        name: "第二航廈（北側）",
        name_en: "Terminal 2 (North)",
        terminal: "T2",
        track: "north",
        lon: 121.23385,
        lat: 25.07662,
        note: "管制區內 · 2F C/D 區（近 C6、D5 登機門）"
      },
      {
        ref: "ST1S",
        name: "第一航廈（南側）",
        name_en: "Terminal 1 (South)",
        terminal: "T1",
        track: "south",
        lon: 121.23735,
        lat: 25.07872,
        note: "管制區外 · 1F 郵局旁（依指標前往）"
      },
      {
        ref: "ST2S",
        name: "第二航廈（南側）",
        name_en: "Terminal 2 (South)",
        terminal: "T2",
        track: "south",
        lon: 121.23363,
        lat: 25.07646,
        note: "管制區外 · 3F 22 號報到櫃台旁（依指標前往）"
      }
    ].freeze

    def self.build!(line)
      new(line).build!
    end

    def self.refresh_all_tra_stations!
      reset_tra_station_cache!
      TraCatalog::LINES.each do |line|
        new(line).refresh_tra_stations!
      rescue StandardError => error
        warn "Skipped #{line.slug} station refresh: #{error.message}"
      end
    end

    def initialize(line)
      @line = line
    end

    def build!
      @route_features = build_route_features

      raise "No track geometry for #{@line.slug}" if @route_features.empty?

      extend_routes_for_depots!(@route_features)

      stations = fetch_stations_for_line
      apply_taichung_station_coordinates!(stations) if @line.system_id == "taichung_metro"
      align_stations_to_routes!(stations, @route_features)
      align_tra_junction_station!(stations) if @line.system_id == "tra"
      apply_tra_route_terminals!(@route_features, stations) if @line.system_id == "tra"
      assign_tra_station_terminal_roles!(stations) if @line.system_id == "tra"
      reorder_tra_stations!(stations) if tra_station_ordered_line?
      stitch_tra_route_features! if @line.system_id == "tra"

      collection = {
        type: "FeatureCollection",
        name: "#{@line.network_name}#{@line.name}",
        properties: {
          source: geometry_source_note,
          network: @line.network_name,
          ref: @line.ref,
          osm_relations: @line.relation_ids,
          osm_ways: @line.slug == "taoyuan_airport_skytrain" ? SKYTRAIN_TRACKS.map { |t| t[:way_id] } : @line.way_ids
        }.compact,
        features: @route_features + station_features(stations)
      }

      path = output_dir.join("#{@line.slug}.geojson")
      FileUtils.mkdir_p(output_dir)
      File.write(path, JSON.pretty_generate(collection))

      puts "Wrote #{path} (#{@route_features.length} route segments, #{stations.length} stations)"
    end

    def refresh_tra_stations!
      path = output_dir.join("#{@line.slug}.geojson")
      return unless path.exist?

      data = JSON.parse(path.read)
      @route_features = route_features_from_geojson(data)
      return if @route_features.empty?

      repair_tra_route_geometry! unless skip_tra_route_geometry_repair?
      stations = fetch_tra_stations
      align_stations_to_routes!(stations, @route_features)
      align_tra_junction_station!(stations)
      apply_tra_route_terminals!(@route_features, stations) unless skip_tra_route_refresh_geometry_mutation?
      assign_tra_station_terminal_roles!(stations)
      reorder_tra_stations!(stations) if tra_station_ordered_line?
      stitch_tra_route_features! unless skip_tra_route_refresh_geometry_mutation?

      collection = {
        type: data["type"],
        name: data["name"],
        properties: data["properties"],
        features: @route_features + station_features(stations)
      }

      File.write(path, JSON.pretty_generate(collection))
      puts "Refreshed #{path} (#{stations.length} stations with shared refs)"
    end

    private

    def route_features_from_geojson(data)
      data.fetch("features", []).filter_map do |feature|
        next unless feature.dig("properties", "feature_type") == "route"

        geometry = feature["geometry"] || {}
        coordinates = geometry["coordinates"] || geometry[:coordinates]

        {
          type: feature["type"],
          properties: feature["properties"].transform_keys(&:to_sym),
          geometry: {
            type: geometry["type"] || geometry[:type],
            coordinates: coordinates
          }
        }
      end
    end

    def output_dir
      Rails.root.join("public/geojson", @line.output_subdir)
    end

    def build_route_features
      return build_skytrain_route_features if @line.slug == "taoyuan_airport_skytrain"
      return build_tra_route_features if @line.system_id == "tra"
      return build_per_relation_route_features if multi_branch_line?

      build_single_track_route_features
    end

    # Multiple OSM relations that are separate branches (not forward/back duplicates).
    def multi_branch_line?
      %w[danhai_lrt zhonghe_xinlu].include?(@line.slug)
    end

    # Danhai (綠山／藍海) and 中和新蘆線 (主線／蘆洲支線) each need their own track.
    def build_per_relation_route_features
      route_features = []

      @line.relation_ids.each_with_index do |relation_id, relation_index|
        ways = OsmRouteExtractor.new(relation_id: relation_id).fetch_way_elements
        stitcher = OsmRouteExtractor.new(relation_id: relation_id)
        line_strings = ways.empty? ? [] : stitcher.stitch_line_strings(ways)

        if line_strings.empty?
          line_strings = branch_track_fallback(relation_id, relation_index) || []
        end

        line_strings.each_with_index do |coordinates, index|
          route_features << route_feature(coordinates, branch_index: index, relation_index: relation_index)
        end
      end

      route_features
    end

    def branch_track_fallback(relation_id, relation_index)
      return nil unless @line.slug == "zhonghe_xinlu"

      path = Rails.root.join("lib/geojson/fallback_tracks/zhonghe_luzhou_branch.json")
      return nil unless relation_id == @line.relation_ids.first && path.exist?

      coordinates = JSON.parse(path.read)
      coordinates.is_a?(Array) && coordinates.any? ? [ coordinates ] : nil
    end
    alias build_danhai_route_features build_per_relation_route_features

    # Forward/back OSM relations describe the same track; keep one LineString per line.
    def build_single_track_route_features
      route_features = []
      coordinates = longest_route_coordinates

      if coordinates
        route_features << route_feature(coordinates, branch_index: 0, relation_index: 0)
      end

      @line.way_ids.each_with_index do |way_id, way_index|
        ways = OsmRouteExtractor.fetch_way_elements(way_id)
        next if ways.empty?

        stitcher = OsmRouteExtractor.new(relation_id: @line.relation_ids.first || 0)
        stitcher.stitch_line_strings(ways).each_with_index do |coords, index|
          route_features << route_feature(coords, branch_index: index, relation_index: way_index)
        end
      end

      route_features
    end

    def longest_route_coordinates
      best = nil

      @line.relation_ids.each do |relation_id|
        ways = OsmRouteExtractor.new(relation_id: relation_id).fetch_way_elements
        next if ways.empty?

        stitcher = OsmRouteExtractor.new(relation_id: relation_id)
        stitcher.stitch_line_strings(ways).each do |chain|
          best = chain if best.nil? || chain.length > best.length
        end
      end

      best
    end

    TRA_CHAIN_GAP_MAIN_M = 2_000
    TRA_CHAIN_GAP_BRANCH_M = 800
    TRA_CHAIN_GAP_FRAGMENT_M = 45_000
    TRA_CHAIN_GAP_STITCH_MIN_M = 400
    TRA_CHAIN_GAP_STITCH_STEP_M = 250

    def build_tra_route_features
      case @line.slug
      when "sea_line"
        build_tra_cached_or_station_ordered_route_features(
          station_refs: SEA_LINE_STATION_REFS
        )
      when "mountain_line"
        build_tra_cached_or_station_ordered_route_features(
          station_refs: MOUNTAIN_STATION_REFS
        )
      when "beihui_line"
        build_tra_cached_or_station_ordered_route_features(
          station_refs: BEIHUI_STATION_REFS
        )
      when "taidong_line"
        build_tra_cached_or_station_ordered_route_features(
          station_refs: TAIDONG_STATION_REFS
        )
      when "yilan_line"
        build_tra_cached_or_station_ordered_route_features(
          station_refs: YILAN_STATION_REFS
        )
      when "neiwan_line"
        build_tra_cached_or_station_ordered_route_features(
          station_refs: NEIWAN_STATION_REFS
        )
      when "liujia_line"
        build_tra_station_ordered_route_features(
          station_refs: LIUJIA_STATION_REFS
        )
      when "jiji_line"
        build_tra_cached_or_station_ordered_route_features(
          station_refs: JIJI_STATION_REFS
        )
      when "pingxi_line"
        build_tra_cached_or_station_ordered_route_features(
          station_refs: PINGXI_STATION_REFS
        )
      when "shenao_line"
        build_tra_cached_or_station_ordered_route_features(
          station_refs: SHENAO_STATION_REFS
        )
      when "chengzhui_line"
        build_tra_cached_or_station_ordered_route_features(
          station_refs: CHENGZHUI_STATION_REFS
        )
      when "shalun_line"
        build_tra_cached_or_station_ordered_route_features(
          station_refs: SHALUN_STATION_REFS
        )
      when "hualien_port_line"
        build_tra_cached_or_station_ordered_route_features(
          station_refs: HUALIEN_PORT_STATION_REFS
        )
      when "taichung_port_line"
        build_tra_cached_or_station_ordered_route_features(
          station_refs: TAICHUNG_PORT_STATION_REFS
        )
      when "pingtung_line"
        build_tra_cached_or_station_ordered_route_features(
          station_refs: PINGTUNG_STATION_REFS
        )
      when "south_link"
        build_tra_cached_or_station_ordered_route_features(
          station_refs: SOUTH_LINK_STATION_REFS
        )
      when "western_trunk_north"
        build_tra_station_ordered_route_features(
          station_refs: WESTERN_TRUNK_NORTH_STATION_REFS
        )
      when "western_trunk_south"
        build_tra_cached_or_station_ordered_route_features(
          station_refs: WESTERN_TRUNK_SOUTH_STATION_REFS
        )
      else
        build_tra_standard_route_features
      end
    end

    TRA_CHAIN_GAP_CONNECT_M = 8_000

    def build_tra_standard_route_features
      chains = tra_route_chains
      return [] if chains.empty?

      gap_threshold = if TraCatalog::BRANCH_SLUGS.include?(@line.slug)
        TRA_CHAIN_GAP_BRANCH_M
      else
        TRA_CHAIN_GAP_CONNECT_M
      end
      primary = tra_primary_merged_chain(chains, gap_threshold_m: gap_threshold)
      return [] unless primary

      finish_tra_route_feature(primary)
    end

    def build_tra_station_ordered_route_features(station_refs:, gap_threshold_m: nil)
      chains = tra_route_chains
      return [] if chains.empty?

      corridor = extract_tra_station_pair_corridor(chains, station_refs)
      return [] unless corridor&.length.to_i >= 2

      finish_tra_route_feature(corridor)
    end

    def build_tra_cached_or_station_ordered_route_features(station_refs:)
      fallback = tra_track_fallback_coordinates
      return finish_tra_route_feature(fallback.dup) if fallback

      build_tra_station_ordered_route_features(station_refs: station_refs)
    end

    def extract_tra_station_ordered_corridor(chain, station_refs)
      stations = station_refs.filter_map do |ref|
        station = self.class.tra_station_by_ref[ref]
        next unless station

        station.merge(ref: ref)
      end

      return chain if stations.length < 2

      start_idx = nearest_chain_index(chain, stations.first[:lon], stations.first[:lat])
      combined = [ chain[start_idx].dup ]
      current_idx = start_idx
      direction = nil

      stations.each_cons(2) do |_from, to|
        to_idx, step_direction = nearest_chain_index_relative(
          chain,
          to[:lon],
          to[:lat],
          from_index: current_idx,
          direction: direction
        )
        direction ||= step_direction
        segment = chain_segment_between(chain, current_idx, to_idx)
        combined.concat(segment.drop(1)) if segment.length > 1
        current_idx = to_idx
      end

      combined.length >= 2 ? combined : chain
    end

    def nearest_chain_index_relative(chain, lon, lat, from_index:, direction:)
      forward = nearest_chain_index_in_range(chain, lon, lat, from_index..(chain.length - 1))
      backward = from_index.positive? ? nearest_chain_index_in_range(chain, lon, lat, 0..from_index) : nil

      if direction == :forward
        [ forward, :forward ]
      elsif direction == :backward
        [ backward || forward, :backward ]
      elsif backward.nil? || forward_distance(chain, lon, lat, forward) <= forward_distance(chain, lon, lat, backward)
        [ forward, :forward ]
      else
        [ backward, :backward ]
      end
    end

    def nearest_chain_index_in_range(chain, lon, lat, range)
      best_index = range.first
      best_distance = Float::INFINITY

      range.each do |index|
        distance = tra_endpoint_gap(chain[index], [ lon, lat ])
        next unless distance < best_distance

        best_distance = distance
        best_index = index
      end

      best_index
    end

    def forward_distance(chain, lon, lat, index)
      tra_endpoint_gap(chain[index], [ lon, lat ])
    end

    def chain_segment_between(chain, from_idx, to_idx)
      return [ chain[from_idx] ] if from_idx == to_idx

      if to_idx >= from_idx
        chain[from_idx..to_idx]
      else
        chain[to_idx..from_idx].reverse
      end
    end

    def nearest_chain_index(chain, lon, lat)
      index = chain_index_for_station({ lon: lon, lat: lat }, [ chain ])
      index.clamp(0, chain.length - 1).floor
    end

    def build_tra_fragmented_route_features(gap_threshold_m:)
      chains = tra_route_chains
      return [] if chains.empty?

      primary = tra_primary_merged_chain(chains, gap_threshold_m: gap_threshold_m)
      return [] unless primary

      finish_tra_route_feature(primary)
    end

    def build_tra_sea_line_route_features
      chains = tra_route_chains
      return [] if chains.empty?

      corridor = extract_tra_station_pair_corridor(chains, SEA_LINE_STATION_REFS)
      return [] unless corridor

      finish_tra_route_feature(corridor)
    end

    TRA_STATION_PAIR_MAX_DETOUR_RATIO = 1.85
    TRA_STATION_PAIR_FALLBACK_DETOUR_RATIO = 2.75
    TRA_STATION_PAIR_MAX_SNAP_M = 5_000

    def extract_tra_station_pair_corridor(chains, station_refs)
      stations = station_refs.filter_map do |ref|
        station = self.class.tra_station_by_ref[ref]
        next unless station

        station.merge(ref: ref)
      end

      return nil if stations.length < 2

      merged_chain = tra_primary_merged_chain(chains, gap_threshold_m: TRA_CHAIN_GAP_MAIN_M)
      combined = []
      merged_hint_idx = nil

      stations.each_cons(2) do |from_station, to_station|
        segment = best_tra_corridor_segment_between(
          chains,
          from_station[:lon], from_station[:lat],
          to_station[:lon], to_station[:lat],
          max_detour_ratio: TRA_STATION_PAIR_MAX_DETOUR_RATIO
        )
        segment ||= best_tra_corridor_segment_between(
          chains,
          from_station[:lon], from_station[:lat],
          to_station[:lon], to_station[:lat],
          max_detour_ratio: TRA_STATION_PAIR_FALLBACK_DETOUR_RATIO
        )
        segment ||= merged_chain && tra_corridor_segment_on_chain(
          merged_chain,
          from_station[:lon], from_station[:lat],
          to_station[:lon], to_station[:lat],
          from_index: merged_hint_idx
        )

        return nil unless segment

        if combined.empty?
          combined.concat(segment)
        else
          combined.concat(segment.drop(1))
        end

        merged_hint_idx = nearest_chain_index(merged_chain, to_station[:lon], to_station[:lat]) if merged_chain
      end

      combined.length >= 2 ? combined : nil
    end

    def tra_corridor_segment_on_chain(chain, from_lon, from_lat, to_lon, to_lat, from_index: nil)
      return nil unless chain&.length.to_i >= 2

      from_idx = from_index || nearest_chain_index(chain, from_lon, from_lat)
      to_idx, = nearest_chain_index_relative(
        chain,
        to_lon,
        to_lat,
        from_index: from_idx,
        direction: nil
      )
      segment = chain_segment_between(chain, from_idx, to_idx)
      return nil if segment.length < 2

      straight = TrackGeometry.planar_distance_meters(from_lon, from_lat, to_lon, to_lat)
      path = tra_path_length_meters(segment)
      ratio = straight.positive? ? path / straight : Float::INFINITY
      return nil if ratio > TRA_STATION_PAIR_FALLBACK_DETOUR_RATIO

      segment
    end

    def best_tra_corridor_segment_between(chains, from_lon, from_lat, to_lon, to_lat, max_detour_ratio:)
      straight = TrackGeometry.planar_distance_meters(from_lon, from_lat, to_lon, to_lat)
      return [ [ from_lon, from_lat ], [ to_lon, to_lat ] ] if straight < 50

      best = nil

      chains.each do |chain|
        next unless chain.length >= 2

        from_indices = chain_indices_near(chain, from_lon, from_lat, TRA_STATION_PAIR_MAX_SNAP_M)
        to_indices = chain_indices_near(chain, to_lon, to_lat, TRA_STATION_PAIR_MAX_SNAP_M)

        from_indices.each do |from_idx|
          to_indices.each do |to_idx|
            next if from_idx == to_idx

            segment = chain_segment_between(chain, from_idx, to_idx)
            next if segment.length < 2

            path = tra_path_length_meters(segment)
            ratio = straight.positive? ? path / straight : Float::INFINITY
            next if ratio > max_detour_ratio

            if best.nil? || path < best[:path]
              best = { segment: segment, path: path }
            end
          end
        end
      end

      best&.dig(:segment)
    end

    def chain_indices_near(chain, lon, lat, max_distance_m)
      index = nearest_chain_index(chain, lon, lat)
      distance = tra_endpoint_gap(chain[index], [ lon, lat ])
      return [] if distance > max_distance_m

      [ index ]
    end

    def tra_path_length_meters(coordinates)
      coordinates.each_cons(2).sum do |start, finish|
        TrackGeometry.planar_distance_meters(start[0], start[1], finish[0], finish[1])
      end
    end

    def tra_join_latitude_ordered_segments(segments)
      ordered = segments.select { |chain| chain.length >= 2 }
        .sort_by { |chain| -chain.map { |point| point[1] }.sum / chain.length }
      return nil if ordered.empty?
      return ordered.first if ordered.length == 1

      combined = ordered.shift.dup
      ordered.each do |segment|
        segment_copy = segment.dup
        next if connect_nearest_tra_chain!(combined, [ segment_copy ], gap_threshold_m: TRA_CHAIN_GAP_MAIN_M)

        south_idx = combined.each_with_index.min_by { |point, _index| point[1] }[1]
        north_idx = segment_copy.each_with_index.max_by { |point, _index| point[1] }[1]
        gap = tra_endpoint_gap(combined[south_idx], segment_copy[north_idx])
        next if gap > TRA_CHAIN_GAP_FRAGMENT_M

        extension = north_idx.zero? ? segment_copy : segment_copy.reverse
        if south_idx == combined.length - 1
          combined.concat(extension[1..] || [])
        elsif south_idx.zero?
          combined.replace((extension[0..-2] || []) + combined)
        else
          connect_nearest_tra_chain!(combined, [ segment_copy ], gap_threshold_m: TRA_CHAIN_GAP_FRAGMENT_M)
        end
      end

      combined
    end

    def build_tra_beihui_line_route_features
      combined = tra_junction_linked_chain(
        junction_lon: TraCatalog::HUALIEN_JUNCTION_LON,
        junction_lat: TraCatalog::HUALIEN_JUNCTION_LAT
      )
      return [] unless combined

      corridor = tra_beihui_loop_chain?(combined) ? extract_tra_beihui_corridor(combined) : combined
      finish_tra_route_feature(corridor)
    end

    def tra_junction_linked_chain(junction_lon:, junction_lat:)
      chains_by_relation = tra_route_chains_by_relation
      if chains_by_relation.empty?
        fallback = tra_track_fallback_coordinates
        return fallback&.dup
      end

      relation_chains = chains_by_relation.values.filter_map do |chains|
        tra_primary_merged_chain(chains, gap_threshold_m: TRA_CHAIN_GAP_FRAGMENT_M)
      end

      return relation_chains.first if relation_chains.length == 1
      return nil if relation_chains.empty?

      combined = relation_chains.shift.dup
      relation_chains.each do |other|
        other_copy = other.dup
        connected = connect_nearest_tra_chain!(combined, [ other_copy ], gap_threshold_m: TRA_CHAIN_GAP_FRAGMENT_M)
        next if connected

        bridge_tra_corridor_segments!(
          combined,
          other_copy,
          junction_lon,
          junction_lat,
          max_gap_m: TRA_CHAIN_GAP_FRAGMENT_M
        )
      end

      combined
    end

    def tra_beihui_loop_chain?(chain)
      return false if chain.length < 2

      lats = chain.map { |point| point[1] }
      chain.first[1] > 24.5 && chain.last[1] > 24.5 && lats.min < 24.0
    end

    def extract_tra_beihui_corridor(chain)
      south_idx = chain.each_with_index.min_by { |point, _index| point[1] }[1]
      north_idx = chain.each_with_index.max_by { |point, _index| point[1] }[1]

      suao_to_hualien = tra_chain_path_between(chain, north_idx, south_idx)
      hualien_to_suao = tra_chain_path_between(chain, south_idx, north_idx).reverse

      if suao_to_hualien.first[1] >= suao_to_hualien.last[1]
        suao_to_hualien
      else
        hualien_to_suao
      end
    end

    def tra_chain_path_between(chain, start_idx, end_idx)
      if start_idx <= end_idx
        chain[start_idx..end_idx]
      else
        chain[start_idx..] + chain[0..end_idx]
      end
    end

    def build_tra_junction_linked_route_features(junction_lon:, junction_lat:)
      combined = tra_junction_linked_chain(junction_lon: junction_lon, junction_lat: junction_lat)
      return [] unless combined

      finish_tra_route_feature(combined)
    end

    def bridge_tra_corridor_segments!(chain, other, junction_lon, junction_lat, max_gap_m: TRA_CHAIN_GAP_MAIN_M)
      junction = [ junction_lon, junction_lat ]
      chain_end = nearest_chain_endpoint_to(chain, junction)
      other_end = nearest_chain_endpoint_to(other, junction)
      return false unless chain_end && other_end

      gap = tra_endpoint_gap(chain_end[:point], other_end[:point])
      return false if gap > max_gap_m

      extension = other_end[:index].zero? ? other : other.reverse
      if chain_end[:index] == chain.length - 1
        chain.concat(extension[1..] || [])
      else
        chain.replace(extension[0..-2] + chain)
      end

      true
    end

    def nearest_chain_endpoint_to(chain, target)
      endpoints = [ [ 0, chain.first ], [ chain.length - 1, chain.last ] ]
      best = endpoints.min_by { |_index, point| tra_endpoint_gap(point, target) }
      return unless best

      { index: best[0], point: best[1] }
    end

    def finish_tra_route_feature(coordinates)
      return [] if coordinates.length < 2

      corridor = extract_tra_north_peak_corridor_if_needed(coordinates.dup)
      prune_tra_corridor_backtracks!(corridor)
      dedupe_tra_coordinates!(corridor)
      orient_tra_line!(corridor)
      clip_tra_coordinates!(corridor)
      stitch_tra_coordinates!(corridor)
      dedupe_tra_coordinates!(corridor)
      return [] if corridor.length < 2

      [ route_feature(corridor, branch_index: 0, relation_index: 0) ]
    end

    def extract_tra_north_peak_corridor_if_needed(chain)
      return chain if @line.slug.in?(%w[
        sea_line neiwan_line liujia_line jiji_line yilan_line
        pingxi_line shenao_line chengzhui_line shalun_line
      ])

      return chain unless tra_line_orientation(0) == :north_to_south

      north_idx = chain.each_with_index.max_by { |point, _index| point[1] }[1]
      south_idx = chain.each_with_index.min_by { |point, _index| point[1] }[1]
      return chain unless tra_loop_chain?(chain, north_idx, south_idx)

      forward = tra_chain_path_between(chain, north_idx, south_idx)
      backward = tra_chain_path_between(chain, south_idx, north_idx).reverse

      if forward.first[1] >= forward.last[1]
        forward
      else
        backward
      end
    end

    def tra_loop_chain?(chain, north_idx, south_idx)
      return false unless north_idx > 0 && north_idx < chain.length - 1

      min_lat = chain[south_idx][1]
      chain.first[1] <= min_lat + 0.05 && chain.last[1] <= min_lat + 0.05
    end

    def repair_tra_route_geometry!
      route = @route_features.find { |feature| feature.dig(:properties, :feature_type) == "route" }
      coordinates = route&.dig(:geometry, :coordinates)
      return unless coordinates.is_a?(Array) && coordinates.length >= 2

      repaired = extract_tra_north_peak_corridor_if_needed(coordinates.dup)
      prune_tra_corridor_backtracks!(repaired)
      dedupe_tra_coordinates!(repaired)
      orient_tra_line!(repaired)
      clip_tra_coordinates!(repaired)
      stitch_tra_coordinates!(repaired)
      dedupe_tra_coordinates!(repaired)
      coordinates.replace(repaired)
    end

    def skip_tra_route_geometry_repair?
      @line.slug.in?(%w[
        sea_line neiwan_line liujia_line jiji_line yilan_line
        pingxi_line shenao_line chengzhui_line shalun_line
        beihui_line taidong_line
      ])
    end

    def skip_tra_route_refresh_geometry_mutation?
      skip_tra_route_geometry_repair?
    end

    def stitch_tra_route_features!
      route = @route_features.find { |feature| feature.dig(:properties, :feature_type) == "route" }
      coordinates = route&.dig(:geometry, :coordinates)
      return unless coordinates.is_a?(Array) && coordinates.length >= 2

      stitch_tra_coordinates!(coordinates)
    end

    def stitch_tra_coordinates!(coordinates, max_gap_m: TRA_CHAIN_GAP_FRAGMENT_M, step_m: TRA_CHAIN_GAP_STITCH_STEP_M,
                                min_gap_m: TRA_CHAIN_GAP_STITCH_MIN_M)
      stitched = [ coordinates.first ]

      coordinates.each_cons(2) do |start, finish|
        gap = tra_endpoint_gap(start, finish)
        if gap > min_gap_m && gap <= max_gap_m
          steps = (gap / step_m).ceil
          (1...steps).each do |step|
            ratio = step.to_f / steps
            stitched << [
              start[0] + ((finish[0] - start[0]) * ratio),
              start[1] + ((finish[1] - start[1]) * ratio)
            ]
          end
        end

        stitched << finish
      end

      coordinates.replace(stitched)
    end

    def prune_tra_corridor_backtracks!(coordinates, tolerance_m: 120, min_detour_m: 800)
      return if coordinates.length < 4

      index = 0
      while index < coordinates.length - 2
        pruned = false
        ((index + 2)...coordinates.length).each do |later|
          shortcut = tra_endpoint_gap(coordinates[index], coordinates[later])
          next if shortcut > tolerance_m

          detour = tra_path_length_meters(coordinates[index..later])
          next if detour < min_detour_m

          coordinates.slice!(index + 1, later - index - 1)
          pruned = true
          break
        end

        index += 1 unless pruned
      end
    end

    def dedupe_tra_coordinates!(coordinates, min_distance_m: 3)
      return if coordinates.length < 2

      deduped = [ coordinates.first ]
      coordinates.each_cons(2) do |previous, point|
        next if tra_endpoint_gap(previous, point) < min_distance_m

        deduped << point
      end

      coordinates.replace(deduped)
    end

    def tra_primary_merged_chain(chains, gap_threshold_m:)
      merged = merge_connectable_chains(chains, gap_threshold_m: gap_threshold_m)
      select_tra_primary_chain(merged)
    end

    def select_tra_primary_chain(merged)
      merged.max_by { |chain| tra_chain_extent_meters(chain) }
    end

    def tra_chain_extent_meters(chain)
      return 0 if chain.length < 2

      lons = chain.map { |point| point[0] }
      lats = chain.map { |point| point[1] }
      TrackGeometry.planar_distance_meters(lons.min, lats.min, lons.max, lats.max)
    end

    def build_tra_parallel_route_features
      gap_threshold = TRA_CHAIN_GAP_MAIN_M

      @line.relation_ids.flat_map.with_index do |relation_id, relation_index|
        ways = OsmRouteExtractor.new(relation_id: relation_id).fetch_way_elements
        next [] if ways.empty?

        stitcher = OsmRouteExtractor.new(relation_id: relation_id)
        chains = stitcher.stitch_line_strings(ways)
        primary = merge_connectable_chains(chains, gap_threshold_m: gap_threshold).max_by(&:length)
        next [] unless primary&.length.to_i >= 2

        orient_tra_line!(primary, relation_index: relation_index)
        [ route_feature(primary, branch_index: 0, relation_index: relation_index) ]
      end
    end

    def clip_tra_coordinates!(coordinates)
      bounds = TraCatalog::GEO_CLIP_BOUNDS[@line.slug]
      return unless bounds

      filtered = coordinates.select do |lon, lat|
        (bounds[:min_lat].nil? || lat >= bounds[:min_lat]) &&
          (bounds[:max_lat].nil? || lat <= bounds[:max_lat]) &&
          (bounds[:min_lon].nil? || lon >= bounds[:min_lon]) &&
          (bounds[:max_lon].nil? || lon <= bounds[:max_lon])
      end

      return if filtered.length < 2

      coordinates.replace(filtered)
    end

    def tra_route_chains
      chains = tra_route_chains_by_relation.values.flat_map { |relation_chains| relation_chains }
      return chains if chains.any?

      fallback = tra_track_fallback_coordinates
      fallback ? [ fallback ] : []
    end

    def tra_route_chains_by_relation
      if self.class.offline_tra_build? && tra_track_fallback_path.exist?
        return {}
      end

      @line.relation_ids.each_with_object({}) do |relation_id, chains_by_relation|
        ways = OsmRouteExtractor.new(relation_id: relation_id).fetch_way_elements
        next if ways.empty?

        chains = OsmRouteExtractor.new(relation_id: relation_id).stitch_line_strings(ways)
        chains_by_relation[relation_id] = chains if chains.any?
      rescue StandardError => error
        warn "Skipped OSM relation #{relation_id} for #{@line.slug}: #{error.message}"
      end
    end

    def tra_track_fallback_path
      Rails.root.join("lib/geojson/fallback_tracks/tra/#{@line.slug}.json")
    end

    def tra_track_fallback_coordinates
      path = tra_track_fallback_path
      return nil unless path.exist?

      coordinates = JSON.parse(path.read)
      coordinates.is_a?(Array) && coordinates.length >= 2 ? coordinates : nil
    end

    def inject_missing_ordered_tra_stations!(stations, allowed_refs)
      present = stations.map { |station| station[:ref] }.to_set

      allowed_refs.each do |ref|
        next if present.include?(ref)

        station = self.class.tra_station_by_ref[ref]
        next unless station

        stations << station.merge(line: @line.name, position_anchored: true)
      end
    end

    def merge_connectable_chains(chains, gap_threshold_m:)
      remaining = chains.map(&:dup)
      merged = []

      until remaining.empty?
        chain = remaining.shift
        loop do
          break unless connect_nearest_tra_chain!(chain, remaining, gap_threshold_m: gap_threshold_m)
        end

        merged << chain if chain.length >= 2
      end

      merged
    end

    def connect_nearest_tra_chain!(chain, remaining, gap_threshold_m:)
      best = { distance: Float::INFINITY }

      remaining.each_with_index do |other, index|
        [
          [ :append, chain.length - 1, other, 0, false ],
          [ :append, chain.length - 1, other, other.length - 1, true ],
          [ :prepend, 0, other, other.length - 1, false ],
          [ :prepend, 0, other, 0, true ]
        ].each do |mode, chain_index, candidate, candidate_index, reverse|
          dist = tra_endpoint_gap(chain[chain_index], candidate[candidate_index])
          next unless dist <= gap_threshold_m && dist < best[:distance]

          best = {
            distance: dist,
            index: index,
            mode: mode,
            candidate_index: candidate_index,
            reverse: reverse
          }
        end
      end

      return false unless best[:index]

      other = remaining.delete_at(best[:index])
      extension = if best[:reverse]
        other.reverse
      else
        other
      end

      if best[:mode] == :append
        chain.concat(extension[1..] || [])
      else
        chain.replace(extension[0..-2] + chain)
      end

      true
    end

    def tra_endpoint_gap(left, right)
      TrackGeometry.planar_distance_meters(left[0], left[1], right[0], right[1])
    end

    def orient_tra_line!(coordinates, relation_index: 0)
      return if coordinates.length < 2
      return if @line.slug.in?(%w[yilan_line shenao_line])

      case tra_line_orientation(relation_index)
      when :north_to_south
        coordinates.reverse! if coordinates.first[1] < coordinates.last[1]
      when :west_to_east
        coordinates.reverse! if coordinates.first[0] > coordinates.last[0]
      end
    end

    def tra_line_orientation(relation_index = 0)
      case @line.slug
      when "yilan_line", "taidong_line", "south_link", "beihui_line", "pingxi_line", "shenao_line"
        :west_to_east
      when "western_trunk_north", "western_trunk_south", "mountain_line", "sea_line",
           "pingtung_line"
        :north_to_south
      when "jiji_line", "shalun_line", "yilan_line", "pingxi_line", "shenao_line", "chengzhui_line"
        :west_to_east
      else
        :north_to_south
      end
    end

    def build_skytrain_route_features
      stitcher = OsmRouteExtractor.new(relation_id: 0)

      SKYTRAIN_TRACKS.flat_map.with_index do |track, track_index|
        line_strings = skytrain_line_strings_for_track(track[:way_id], stitcher)
        next [] if line_strings.empty?

        line_strings.map.with_index do |coordinates, branch_index|
          route_feature(coordinates, branch_index: branch_index, relation_index: track_index)
        end
      end
    end

    def skytrain_line_strings_for_track(way_id, stitcher)
      ways = OsmRouteExtractor.fetch_way_elements(way_id)
      lines = stitcher.stitch_line_strings(ways) if ways.any?
      return lines if lines&.any?

      fallback = SKYTRAIN_TRACK_FALLBACKS[way_id]
      fallback ? [ fallback ] : []
    rescue StandardError => error
      Rails.logger.warn("Skytrain way #{way_id} OSM fetch failed: #{error.message}")
      fallback = SKYTRAIN_TRACK_FALLBACKS[way_id]
      fallback ? [ fallback ] : []
    end

    def geometry_source_note
      parts = []
      parts << "route relations #{@line.relation_ids.join(', ')}" if @line.relation_ids.any?
      parts << "ways #{@line.way_ids.join(', ')}" if @line.way_ids.any?

      note = parts.any? ? "Track geometry from OpenStreetMap #{parts.join(' and ')}." : "Track geometry from OpenStreetMap ways #{SKYTRAIN_TRACKS.map { |t| t[:way_id] }.join(', ')} (with fallbacks)."
      "#{note} © OpenStreetMap contributors, ODbL."
    end

    def fetch_stations_for_line
      if @line.slug == "taoyuan_airport_skytrain"
        return fetch_skytrain_stations
      end

      if @line.slug == "maokong_gondola"
        return fetch_maokong_gondola_stations
      end

      if @line.system_id == "other"
        return fetch_other_stations
      end

      if @line.slug == "danhai_lrt"
        return fetch_danhai_stations
      end

      if @line.system_id == "taichung_metro"
        return fetch_taichung_stations
      end

      if @line.system_id == "kaohsiung_metro"
        return fetch_kaohsiung_stations
      end

      if @line.system_id == "hsr"
        return fetch_hsr_stations
      end

      if @line.system_id == "tra"
        return fetch_tra_stations
      end

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
        stations = reject_stray_songshan_stations(stations)
        stations = stations.reject { |station| station[:ref] == "G03A" }
        return apply_taipei_in_station_transfers!(stations)
      end

      if @line.slug == "tamsui_xinyi"
        stations = stations.reject { |station| station[:ref].in?(%w[R22A]) }
        return apply_taipei_in_station_transfers!(stations)
      end

      apply_taipei_in_station_transfers!(stations)
    end

    def apply_taipei_in_station_transfers!(stations)
      transfers = TaipeiMetroCatalog::IN_STATION_TRANSFERS_BY_NAME
      inject_missing_in_station_transfers!(stations, transfers)
      stations.replace(apply_in_station_transfers(stations, transfers))
      reject_transfer_stations_not_on_line!(stations, transfers)
    end

    # OSM sometimes attaches other lines' stops to the Songshan–Xindian relation.
    def reject_stray_songshan_stations(stations)
      transfer_names = TaipeiMetroCatalog::IN_STATION_TRANSFERS_BY_NAME.keys

      stations.reject do |station|
        next false if transfer_names.include?(station[:name])

        primary_ref = station[:ref].to_s.split(";").first
        next false if primary_ref.match?(/\AG(0[1-9]|1[0-9]|03A)\z/i)

        true
      end
    end

    def default_stations
      OsmRouteExtractor.new(relation_id: @line.relation_ids.first)
        .fetch_stations(ref_prefix: @line.station_ref_prefix, network: @line.osm_networks)
    end

    def fetch_circular_stations
      extractor = OsmRouteExtractor.new(relation_id: @line.relation_ids.first)
      stops = extractor.fetch_named_stops_from_relation

      stations = stops.filter_map do |stop|
        ref = TaipeiMetroCatalog::CIRCULAR_STATION_REFS_BY_NAME[stop[:name]]
        next unless ref

        stop.merge(ref: ref)
      end.sort_by { |station| station_sort_key(station[:ref]) }

      apply_taipei_in_station_transfers!(stations)
    end

    def fetch_taichung_stations
      stations = OsmRouteExtractor.new(relation_id: @line.relation_ids.first)
        .fetch_stations_by_network(@line.osm_networks)

      stations = merge_stations(stations, TaichungMetroCatalog::FALLBACK_STATIONS)
      apply_taichung_station_coordinates!(stations)
      stations
    end

    def apply_taichung_station_coordinates!(stations)
      TaichungMetroCatalog::FALLBACK_STATIONS.each do |fallback|
        station = stations.find do |entry|
          entry[:ref] == fallback[:ref] || entry[:name] == fallback[:name]
        end
        next unless station

        station.merge!(
          lon: fallback[:lon],
          lat: fallback[:lat],
          name: fallback[:name],
          position_anchored: true
        )
      end
    end

    def extend_routes_for_depots!(route_features)
      line_strings = route_line_strings(route_features)
      return if line_strings.empty?

      MetroDepotCatalog.depots_for_route(@line.slug).each do |depot|
        spur = TrackGeometry.depot_link_coordinates_for_point(depot[:lon], depot[:lat], line_strings)
        next unless spur

        route_features << depot_spur_feature(spur, depot)
      end
    end

    def depot_spur_feature(coordinates, depot)
      {
        type: "Feature",
        properties: {
          feature_type: "depot_spur",
          ref: @line.ref,
          name: "#{depot[:name]}支線",
          color: @line.color,
          depot_id: depot[:id]
        },
        geometry: {
          type: "LineString",
          coordinates: coordinates
        }
      }
    end

    def fetch_hsr_stations
      HsrCatalog::FALLBACK_STATIONS.map do |fallback|
        fallback.merge(line: @line.name)
      end
    end

    TRA_BRANCH_SLUGS = TraCatalog::BRANCH_SLUGS.freeze
    TRA_MAIN_NEAR_TRACK_M = 650
    TRA_BRANCH_NEAR_TRACK_M = 400

    def self.tra_station_cache
      @tra_station_cache ||= begin
        cached = Geojson::TraStationCatalog.cached_stations
        if offline_tra_build? && cached.any?
          cached
        else
          begin
            osm = OsmRouteExtractor.new(relation_id: 0).fetch_tra_stations
            merge_tra_station_sources(cached, osm)
          rescue StandardError => error
            if cached.any?
              warn "TRA station OSM fetch failed, using cache: #{error.message}"
              cached
            else
              raise
            end
          end
        end
      end
    end

    def self.merge_tra_station_sources(*sources)
      sources.flatten.compact.each_with_object({}) do |station, by_ref|
        ref = normalize_tra_station_ref_class(station[:ref] || station["ref"])
        next if ref.blank?

        name = (station[:name] || station["name"]).to_s.strip.sub(/車站\z/, "")
        next if name.blank?

        by_ref[ref] = {
          ref: ref,
          name: name,
          lon: station[:lon] || station["lon"],
          lat: station[:lat] || station["lat"]
        }
      end.values
    end

    def self.reset_tra_station_cache!
      @tra_station_cache = nil
      @tra_junction_coordinates = nil
      @tra_station_by_ref = nil
    end

    def self.offline_tra_build?
      @offline_tra_build == true
    end

    def self.offline_tra_build=(value)
      @offline_tra_build = value
    end

    def fetch_tra_stations
      line_strings = route_line_strings(@route_features || build_route_features)
      return [] if line_strings.empty?

      threshold_m = TRA_BRANCH_SLUGS.include?(@line.slug) ? TRA_BRANCH_NEAR_TRACK_M : TRA_MAIN_NEAR_TRACK_M
      candidates = self.class.tra_station_cache

      near_track = candidates.filter_map do |station|
        _track_lon, _track_lat, distance = TrackGeometry.nearest_on_line_strings(
          station[:lon],
          station[:lat],
          line_strings
        )
        next if distance > threshold_m

        normalized_name = normalize_tra_station_name(station[:name])
        next if normalized_name.blank?

        ref = normalize_tra_station_ref(station[:ref])
        next if ref.blank?
        next if Geojson::TraStationCatalog.excluded_refs_for(@line.slug).include?(ref)

        canonical = self.class.tra_station_by_ref[ref]
        station.merge(
          name: canonical&.fetch(:name) || normalized_name,
          ref: ref,
          lon: canonical&.fetch(:lon) || station[:lon],
          lat: canonical&.fetch(:lat) || station[:lat],
          line: @line.name
        )
      end

      if tra_station_ordered_line?
        allowed = tra_station_order_refs.to_set
        near_track.select! { |station| allowed.include?(station[:ref]) }
        inject_missing_ordered_tra_stations!(near_track, allowed)
      end

      clip_tra_station_candidates!(dedupe_tra_stations(near_track))
        .then { |list| TransitTransferCatalog.apply_tra_transfers!(list, line: @line) }
        .sort_by { |station| chain_index_for_station(station, line_strings) }
    end

    def align_tra_junction_station!(stations)
      return unless western_trunk_junction_line?

      stations.each do |station|
        next unless station[:ref] == TraCatalog::WESTERN_TRUNK_JUNCTION_REF

        station.merge!(
          name: TraCatalog::WESTERN_TRUNK_JUNCTION_NAME,
          lon: TraCatalog::WESTERN_TRUNK_JUNCTION_LON,
          lat: TraCatalog::WESTERN_TRUNK_JUNCTION_LAT,
          position_anchored: true
        )
      end
    end

    def western_trunk_junction_line?
      @line.slug.in?(%w[western_trunk_north western_trunk_south])
    end

    def clip_tra_station_candidates!(stations)
      bounds = TraCatalog::GEO_CLIP_BOUNDS[@line.slug]
      return stations unless bounds

      stations.select { |station| tra_station_within_clip_bounds?(station, bounds) }
    end

    def tra_station_within_clip_bounds?(station, bounds)
      (bounds[:min_lat].nil? || station[:lat] >= bounds[:min_lat]) &&
        (bounds[:max_lat].nil? || station[:lat] <= bounds[:max_lat])
    end

    def normalize_tra_station_name(name)
      name.to_s.strip.sub(/車站\z/, "")
    end

    def normalize_tra_station_ref(raw_ref)
      ref = raw_ref.to_s.strip.sub(/\A[A-Z]+-/, "")
      ref.match?(/\A\d+\z/) ? ref : nil
    end

    def dedupe_tra_stations(stations)
      stations.each_with_object({}) do |station, by_ref|
        by_ref[station[:ref]] = station
      end.values
    end

    def self.tra_station_by_ref
      @tra_station_by_ref ||= begin
        by_ref = {}

        tra_station_cache.each do |station|
          ref = normalize_tra_station_ref_class(station[:ref])
          next if ref.blank?

          name = station[:name].to_s.strip.sub(/車站\z/, "")
          next if name.blank?

          by_ref[ref] ||= {
            ref: ref,
            name: name,
            lon: station[:lon],
            lat: station[:lat]
          }
        end

        by_ref
      end
    end

    def self.normalize_tra_station_ref_class(raw_ref)
      ref = raw_ref.to_s.strip.sub(/\A[A-Z]+-/, "")
      ref.match?(/\A\d+\z/) ? ref : nil
    end

    TRA_MAIN_LINE_TERMINAL_ROLES = {
      "western_trunk_north" => { "900" => "origin" },
      "yilan_line" => { "920" => "origin", "7120" => "destination" }
    }.freeze

    def assign_tra_station_terminal_roles!(stations)
      partial = TRA_PARTIAL_TERMINAL_REFS[@line.slug]
      main_line_roles = TRA_MAIN_LINE_TERMINAL_ROLES[@line.slug] || {}

      stations.each do |station|
        ref = canonical_tra_station_ref(station[:ref])
        next unless ref

        if (role = main_line_roles[ref])
          station[:station_role] = role
        elsif TraCatalog::BRANCH_SLUGS.include?(@line.slug) && partial&.dig(:finish) == ref
          station[:station_role] = "destination"
        end
      end
    end

    TRA_PARTIAL_TERMINAL_REFS = {
      "neiwan_line" => { start: "1210", finish: "1208" },
      "liujia_line" => { start: "1194", finish: "1193" },
      "jiji_line" => { start: "3430", finish: "3436" },
      "pingxi_line" => { start: "7330", finish: "7336" },
      "shenao_line" => { start: "7360", finish: "7362" },
      "chengzhui_line" => { start: "3350", finish: "2260" },
      "shalun_line" => { start: "4270", finish: "4272" },
      "hualien_port_line" => { start: "7010", finish: "6256" },
      "taichung_port_line" => { start: "2210", finish: "2211" },
      "pingtung_line" => { start: "4400", finish: "5120" },
      "south_link" => { start: "5130", finish: "6000" },
      "beihui_line" => { start: "7000", finish: "7130" },
      "taidong_line" => { start: "6000", finish: TraCatalog::HUALIEN_JUNCTION_REF },
      "yilan_line" => { start: "920", finish: "7120" },
      "sea_line" => { start: "1250", finish: TraCatalog::WESTERN_TRUNK_JUNCTION_REF },
      "mountain_line" => { start: "1250", finish: TraCatalog::WESTERN_TRUNK_JUNCTION_REF },
      "western_trunk_north" => { start: "900", finish: "1250" },
      "western_trunk_south" => { start: TraCatalog::WESTERN_TRUNK_JUNCTION_REF, finish: "4400" }
    }.freeze

    def apply_tra_route_terminals!(route_features, stations)
      route = route_features.find { |feature| feature.dig(:properties, :feature_type) == "route" }
      coordinates = route&.dig(:geometry, :coordinates)
      return unless coordinates.is_a?(Array) && coordinates.length >= 2

      partial = TRA_PARTIAL_TERMINAL_REFS[@line.slug]
      if partial&.dig(:start) && partial[:finish]
        extend_tra_named_terminals_at_ends!(
          coordinates,
          start_ref: partial[:start],
          finish_ref: partial[:finish],
          stations: stations
        )
        return
      end

      terminals = tra_route_oriented_terminals(stations, coordinates)
      return unless terminals

      start_station = tra_terminal_station(partial&.dig(:start)) || terminals[:start]
      finish_station = tra_terminal_station(partial&.dig(:finish)) || terminals[:finish]
      assign_tra_terminal_coords!(coordinates, start_station, finish_station)
    end

    def extend_tra_named_terminals!(coordinates, start_ref:, finish_ref:)
      start = tra_terminal_station(start_ref)
      finish = tra_terminal_station(finish_ref)
      return unless start && finish

      assign_tra_terminal_coords!(coordinates, start, finish)
    end

    def extend_tra_named_terminals_at_ends!(coordinates, start_ref:, finish_ref:, stations: [])
      start = tra_aligned_terminal_station(stations, start_ref)
      finish = tra_aligned_terminal_station(stations, finish_ref)
      return unless start && finish

      snap_tra_terminal_coordinate!(coordinates, 0, start)
      snap_tra_terminal_coordinate!(coordinates, -1, finish)
    end

    def tra_aligned_terminal_station(stations, ref)
      stations.find { |station| canonical_tra_station_ref(station[:ref]) == ref } || tra_terminal_station(ref)
    end

    def canonical_tra_station_ref(ref)
      ref.to_s.split(";").first.to_s[/\A(\d+)/, 1]
    end

    def assign_tra_terminal_coords!(coordinates, start_station, finish_station)
      start_index, finish_index = tra_terminal_indexes(coordinates)

      snap_tra_terminal_coordinate!(coordinates, start_index, start_station) if start_station
      snap_tra_terminal_coordinate!(coordinates, finish_index, finish_station) if finish_station
    end

    def tra_terminal_indexes(coordinates)
      case tra_line_orientation(0)
      when :west_to_east
        coordinates.first[0] <= coordinates.last[0] ? [ 0, -1 ] : [ -1, 0 ]
      else
        coordinates.first[1] >= coordinates.last[1] ? [ 0, -1 ] : [ -1, 0 ]
      end
    end

    def snap_tra_terminal_coordinate!(coordinates, index, station)
      point = [ station[:lon], station[:lat] ]
      gap = tra_endpoint_gap(coordinates[index], point)
      return if gap > TRA_CHAIN_GAP_FRAGMENT_M

      coordinates[index] = point
    end

    def tra_route_oriented_terminals(stations, coordinates)
      return nil if stations.empty?

      case tra_line_orientation(0)
      when :north_to_south
        north = stations.max_by { |station| station[:lat] }
        south = stations.min_by { |station| station[:lat] }
        if coordinates.first[1] >= coordinates.last[1]
          { start: north, finish: south }
        else
          { start: south, finish: north }
        end
      when :west_to_east
        west = stations.min_by { |station| station[:lon] }
        east = stations.max_by { |station| station[:lon] }
        if coordinates.first[0] <= coordinates.last[0]
          { start: west, finish: east }
        else
          { start: east, finish: west }
        end
      end
    end

    def tra_terminal_station(ref)
      return nil if ref.blank?

      if ref == TraCatalog::WESTERN_TRUNK_JUNCTION_REF
        return {
          lon: TraCatalog::WESTERN_TRUNK_JUNCTION_LON,
          lat: TraCatalog::WESTERN_TRUNK_JUNCTION_LAT,
          name: TraCatalog::WESTERN_TRUNK_JUNCTION_NAME
        }
      end

      self.class.tra_station_by_ref[ref]
    end

    WESTERN_TRUNK_NORTH_STATION_REFS = %w[
      900 910 920 930 940 950 960 970 980 990 1000 1010 1020 1030 1040 1050 1060 1070 1075 1080
      1090 1100 1110 1120 1130 1140 1150 1160 1170 1180 1210 1190 1220 1230 1240 1250
    ].freeze

    WESTERN_TRUNK_SOUTH_STATION_REFS = %w[
      3360 3370 3380 3390 3400 3410 3420 3430 3450 3460 3470 3480 3490 4050 4060 4070 4080 4090
      4100 4110 4120 4130 4140 4150 4160 4170 4180 4190 4200 4210 4220 4250 4260 4270 4290 4300
      4310 4320 4330 4340 4350 4360 4370 4380 4390 4400
    ].freeze

    SEA_LINE_STATION_REFS = %w[
      1250 2110 2120 2130 2140 2150 2160 2170 2180 2190 2200 2210 2220 2230 2240 2250 2260 3360
    ].freeze

    MOUNTAIN_STATION_REFS = %w[
      1250 3140 3150 3160 3170 3180 3190 3210 3220 3230 3240 3250 3260 3270 3280 3290 3300 3310
      3320 3330 3340 3350 3360
    ].freeze

    NEIWAN_STATION_REFS = %w[1210 1190 1191 1192 1193 1201 1202 1203 1204 1205 1206 1207 1208].freeze
    LIUJIA_STATION_REFS = %w[1194 1193].freeze
    JIJI_STATION_REFS = %w[3430 3431 3432 3433 3434 3436].freeze
    PINGXI_STATION_REFS = %w[7330 7331 7332 7333 7334 7335 7336].freeze
    SHENAO_STATION_REFS = %w[7360 7361 7362].freeze
    CHENGZHUI_STATION_REFS = %w[3350 2260].freeze
    SHALUN_STATION_REFS = %w[4270 4271 4272].freeze
    HUALIEN_PORT_STATION_REFS = %w[7010 6256].freeze
    TAICHUNG_PORT_STATION_REFS = %w[2210 2211].freeze
    PINGTUNG_STATION_REFS = %w[
      4400 4410 4420 4430 4440 4450 4460 4470 5000 5010 5020 5030 5040 5050 5060 5070 5080
      5090 5100 5110 5120
    ].freeze
    SOUTH_LINK_STATION_REFS = %w[5130 5140 5160 5190 5200 5210 5220 5230 5240 6000].freeze
    BEIHUI_STATION_REFS = %w[7000 7010 7020 7030 7040 7050 7060 7070 7080 7090 7100 7110 7130].freeze
    TAIDONG_STATION_REFS = %w[
      6000 6010 6020 6030 6040 6050 6060 6070 6080 6090 6100 6110 6120 6130 6140 6150 6160
      6210 6220 6230 6240 6250 7000
    ].freeze
    YILAN_STATION_REFS = %w[
      920 7390 7380 7360 7350 7320 7310 7300 7290 7280 7270 7260 7250 7240 7230 7220 7210 7200
      7190 7180 7170 7160 7150 7120
    ].freeze

    TRA_STATION_ORDERED_LINES = {
      "western_trunk_north" => WESTERN_TRUNK_NORTH_STATION_REFS,
      "western_trunk_south" => WESTERN_TRUNK_SOUTH_STATION_REFS,
      "sea_line" => SEA_LINE_STATION_REFS,
      "mountain_line" => MOUNTAIN_STATION_REFS,
      "neiwan_line" => NEIWAN_STATION_REFS,
      "liujia_line" => LIUJIA_STATION_REFS,
      "jiji_line" => JIJI_STATION_REFS,
      "pingxi_line" => PINGXI_STATION_REFS,
      "shenao_line" => SHENAO_STATION_REFS,
      "chengzhui_line" => CHENGZHUI_STATION_REFS,
      "shalun_line" => SHALUN_STATION_REFS,
      "hualien_port_line" => HUALIEN_PORT_STATION_REFS,
      "pingtung_line" => PINGTUNG_STATION_REFS,
      "south_link" => SOUTH_LINK_STATION_REFS,
      "beihui_line" => BEIHUI_STATION_REFS,
      "taidong_line" => TAIDONG_STATION_REFS,
      "yilan_line" => YILAN_STATION_REFS
    }.freeze

    def tra_station_ordered_line?
      TRA_STATION_ORDERED_LINES.key?(@line.slug)
    end

    def tra_station_order_refs
      TRA_STATION_ORDERED_LINES.fetch(@line.slug)
    end

    def reorder_tra_stations!(stations)
      if tra_station_ordered_line?
        order = tra_station_order_refs.each_with_index.to_h
        if @line.slug == "sea_line"
          stations.select! { |station| order.key?(canonical_tra_station_ref(station[:ref])) }
        end
        stations.sort_by! { |station| order.fetch(canonical_tra_station_ref(station[:ref]), order.length) }
        return
      end

      line_strings = route_line_strings(@route_features)
      return if line_strings.empty?

      stations.sort_by! { |station| chain_index_for_station(station, line_strings) }
    end

    def self.tra_junction_coordinates
      @tra_junction_coordinates ||= tra_station_by_ref.transform_values do |entry|
        entry.slice(:lon, :lat)
      end
    end

    def apply_hsr_station_coordinates!(stations)
      HsrCatalog::FALLBACK_STATIONS.each do |fallback|
        station = stations.find do |entry|
          entry[:ref] == fallback[:ref] || entry[:name] == fallback[:name]
        end
        next unless station

        station.merge!(lon: fallback[:lon], lat: fallback[:lat], name: fallback[:name])
      end
    end

    def normalize_hsr_station_refs!(stations)
      stations.each do |station|
        ref = hsr_ref_for_station_name(station[:name])
        station[:ref] = ref if ref
        station[:line] ||= @line.name
      end
    end

    def hsr_ref_for_station_name(name)
      return nil if name.blank?

      normalized = name.to_s.gsub(/車站|站\z/, "")
      HsrCatalog::STATION_REFS_BY_NAME.each do |station_name, ref|
        return ref if normalized.include?(station_name) || station_name.include?(normalized)
      end

      nil
    end

    def fetch_kaohsiung_stations
      stations = merge_stations(stations_from_relations, default_stations)
      if @line.slug == "red_line"
        stations = merge_stations(stations, KaohsiungMetroCatalog::RED_LINE_FALLBACK_STATIONS)
      end
      transfers = kaohsiung_in_station_transfers_for_line
      inject_missing_in_station_transfers!(stations, transfers)
      stations.replace(apply_in_station_transfers(stations, transfers))
      reject_transfer_stations_not_on_line!(stations, transfers)
    end

    def kaohsiung_in_station_transfers_for_line
      case @line.slug
      when "circular_lrt"
        KaohsiungMetroCatalog::CIRCULAR_LRT_IN_STATION_TRANSFERS_BY_NAME
      when "red_line", "orange_line"
        KaohsiungMetroCatalog::IN_STATION_TRANSFERS_BY_NAME
      else
        {}
      end
    end

    def inject_missing_in_station_transfers!(stations, transfers_by_name)
      transfers_by_name.each do |name, transfer|
        next unless in_station_transfer_applies_to_line?(transfer)
        next if stations.any? { |station| station[:name] == name }

        line_ref = transfer_ref_for_current_line(transfer[:combined_ref])
        next unless line_ref

        stations << {
          ref: line_ref,
          name: name,
          lon: transfer[:lon],
          lat: transfer[:lat]
        }
      end

      stations.sort_by! { |station| station_sort_key(station[:ref]) }
    end

    def reject_transfer_stations_not_on_line!(stations, transfers_by_name)
      stations.reject! do |station|
        transfer = transfers_by_name[station[:name]]
        next false unless transfer

        !in_station_transfer_applies_to_line?(transfer) ||
          transfer_ref_for_current_line(transfer[:combined_ref]).nil?
      end
    end

    def in_station_transfer_applies_to_line?(transfer)
      lines = transfer[:lines]
      lines.nil? || lines.empty? || lines.include?(@line.slug)
    end

    def transfer_ref_for_current_line(combined_ref)
      combined_ref.to_s.split(";").map(&:strip).find do |ref|
        station_ref_belongs_to_current_line?(ref)
      end
    end

    def station_ref_belongs_to_current_line?(ref)
      ref_prefix = ref.to_s[/\A[A-Z]+/i]
      return false unless ref_prefix

      current_line_station_ref_prefixes.include?(ref_prefix.upcase)
    end

    def current_line_station_ref_prefixes
      @current_line_station_ref_prefixes ||= begin
        prefix = @line.station_ref_prefix.to_s.upcase
        prefixes = [ prefix ].reject(&:empty?)
        prefixes = %w[BL] if @line.slug == "bannan"
        prefixes = %w[G] if @line.slug == "songshan_xindian" || @line.slug == "xiaobitan_branch"
        prefixes = %w[R] if @line.slug == "tamsui_xinyi" || @line.slug == "xinbeitou_branch"
        prefixes
      end
    end

    def apply_in_station_transfers(stations, transfers_by_name)
      stations.map do |station|
        transfer = transfers_by_name[station[:name]]
        next station unless transfer && in_station_transfer_applies_to_line?(transfer)

        station.merge(
          ref: transfer[:combined_ref],
          lon: transfer[:lon],
          lat: transfer[:lat]
        )
      end
    end

    def fetch_maokong_gondola_stations
      stations = @line.way_ids.flat_map do |way_id|
        OsmRouteExtractor.fetch_aerialway_stations_for_way(
          way_id,
          ref_prefix: @line.station_ref_prefix,
          include_angle_stations: true
        )
      end

      stations = merge_stations([], stations.map { |station| enrich_maokong_station(station) })
      stations = merge_stations(stations, OtherTransitCatalog::MAOKONG_FALLBACK_STATIONS)
      stations = TransitTransferCatalog.apply_tra_transfers!(stations, line: @line)
      stations.sort_by { |station| maokong_station_sort_key(station[:ref]) }
    end

    def enrich_maokong_station(station)
      return station unless station[:angle_station] || station[:name].match?(/轉角/)

      station.merge(
        angle_station: true,
        passenger_service: false,
        note: "不提供載客服務"
      )
    end

    def maokong_station_sort_key(ref)
      match = ref.to_s.match(/G(\d+)/i)
      match ? match[1].to_i : 99
    end

    def fetch_other_stations
      stations = @line.relation_ids.flat_map do |relation_id|
        OsmRouteExtractor.new(relation_id: relation_id).fetch_stations_from_relation(
          allow_missing_ref: true,
          ref_prefix: @line.station_ref_prefix
        )
      end

      @line.way_ids.each do |way_id|
        stations = merge_stations(
          stations,
          OsmRouteExtractor.fetch_aerialway_stations_for_way(way_id, ref_prefix: @line.station_ref_prefix)
        )
      end

      merge_stations([], stations)
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
      ref = ref.to_s.split(";").first
      prefix = ref[/\A[A-Z]+/] || ""
      numeric = ref[/\d+/]
      suffix = ref.sub(/\A#{Regexp.escape(prefix)}#{numeric}/, "")
      # Taichung 103a (北屯總站) is north of 103 (舊社) on the same number block.
      suffix_rank = if ref.match?(/\A\d+[a-z]\z/i)
        0
      elsif suffix.empty?
        1
      else
        2
      end

      [ prefix, numeric.to_i, suffix_rank, suffix ]
    end

    def route_feature(coordinates, branch_index: 0, relation_index: 0)
      name = route_segment_name(relation_index, branch_index)
      segment = danhai_segment_key(relation_index) || skytrain_segment_key(relation_index)

      {
        type: "Feature",
        properties: {
          feature_type: "route",
          ref: @line.ref,
          name: name,
          name_en: @line.name_en,
          color: danhai_segment_color(segment) || @line.color,
          segment: segment
        }.compact,
        geometry: {
          type: "LineString",
          coordinates: coordinates
        }
      }
    end

    def route_segment_name(relation_index, branch_index)
      if @line.slug == "danhai_lrt"
        segment = %w[綠山線 藍海線][relation_index]
        return "#{@line.name}（#{segment}）" if segment
      end

      if @line.slug == "taoyuan_airport_skytrain"
        track = SKYTRAIN_TRACKS[relation_index]
        if track
          name = "#{@line.name}（#{track[:label]}·#{track[:boarding_area] == 'secured' ? '管制區內' : '管制區外'}）"
          return "#{name} (#{branch_index + 1})" if branch_index.positive?

          return name
        end
      end

      if @line.slug == "zhonghe_xinlu"
        segment = %w[蘆洲支線 新莊線][relation_index]
        return "#{@line.name}（#{segment}）" if segment
      end

      name = @line.name
      name = "#{name} (#{branch_index + 1})" if branch_index.positive?

      name
    end

    def fetch_skytrain_stations
      SKYTRAIN_BOARDING_STATIONS.map do |station|
        track = SKYTRAIN_TRACKS.find { |entry| entry[:segment] == station[:track] }
        side_label = track[:label]

        station.merge(
          line: "#{@line.name}（#{side_label}）",
          color: @line.color,
          segment: station[:track],
          boarding_area: track[:boarding_area]
        )
      end
    end

    def skytrain_segment_key(relation_index)
      return nil unless @line.slug == "taoyuan_airport_skytrain"

      SKYTRAIN_TRACKS[relation_index]&.fetch(:segment)
    end

    def fetch_danhai_stations
      stations_by_ref = {}

      @line.relation_ids.each_with_index do |relation_id, relation_index|
        extractor = OsmRouteExtractor.new(relation_id: relation_id)
        relation_stations = extractor.fetch_stations_from_relation

        if relation_index.zero?
          relation_stations = merge_stations(
            relation_stations,
            extractor.fetch_stations(ref_prefix: @line.station_ref_prefix)
          )
        end

        relation_stations.each { |station| stations_by_ref[station[:ref]] ||= station }
      end

      NewTaipeiMetroCatalog::DANHAI_FALLBACK_STATIONS.each do |station|
        stations_by_ref[station[:ref]] ||= station
      end

      expand_danhai_stations(stations_by_ref.values)
    end

    def expand_danhai_stations(stations)
      stations.sort_by { |station| danhai_station_sort_key(station[:ref]) }.flat_map do |station|
        ref = station[:ref]

        if NewTaipeiMetroCatalog::DANHAI_SHARED_STATION_REFS.include?(ref)
          [
            danhai_station_for_segment(station, "lushan"),
            danhai_station_for_segment(station, "lanhai")
          ]
        elsif NewTaipeiMetroCatalog::DANHAI_LANHAI_ONLY_STATION_REFS.include?(ref)
          [ danhai_station_for_segment(station, "lanhai") ]
        else
          [ danhai_station_for_segment(station, "lushan") ]
        end
      end
    end

    def danhai_station_for_segment(station, segment)
      line_label = segment == "lushan" ? "綠山線" : "藍海線"

      station.merge(
        segment: segment,
        color: danhai_segment_color(segment),
        line: "淡海輕軌（#{line_label}）"
      )
    end

    def danhai_station_sort_key(ref)
      lanhai_index = NewTaipeiMetroCatalog::DANHAI_LANHAI_STATION_ORDER.index(ref)
      return [ 1, lanhai_index ] unless lanhai_index.nil?

      match = ref.to_s.match(/V(\d+)/i)
      [ 0, match ? match[1].to_i : 99 ]
    end

    def danhai_segment_key(relation_index)
      return nil unless @line.slug == "danhai_lrt"

      %w[lushan lanhai][relation_index]
    end

    def danhai_segment_color(_segment)
      @line.color if @line.slug == "danhai_lrt"
    end

    def in_station_transfer_for(name, ref: nil)
      if @line.system_id.in?(%w[taipei_metro kaohsiung_metro])
        legacy = TaipeiMetroCatalog::IN_STATION_TRANSFERS_BY_NAME[name] ||
          KaohsiungMetroCatalog::IN_STATION_TRANSFERS_BY_NAME[name] ||
          KaohsiungMetroCatalog::CIRCULAR_LRT_IN_STATION_TRANSFERS_BY_NAME[name]
        if legacy
          return TransitTransferCatalog::Entry.new(
            combined_ref: legacy[:combined_ref],
            lon: legacy[:lon],
            lat: legacy[:lat]
          )
        end
      end

      TransitTransferCatalog.transfer_for(name, line: @line, ref: ref)
    end

    def route_line_strings(route_features)
      route_features.filter_map do |feature|
        next unless feature.dig(:properties, :feature_type) == "route"

        coordinates = feature.dig(:geometry, :coordinates)
        coordinates if coordinates.is_a?(Array) && coordinates.length >= 2
      end
    end

    def chain_index_for_station(station, line_strings)
      lon = station[:lon]
      lat = station[:lat]
      best_index = 0
      best_distance = Float::INFINITY

      line_strings.each do |coordinates|
        coordinates.each_cons(2).with_index do |(start, finish), segment_index|
          projected_lon, projected_lat, distance = project_point_on_segment(lon, lat, start, finish)
          progress = segment_progress(start, finish, projected_lon, projected_lat)
          index = segment_index + progress

          if distance < best_distance
            best_distance = distance
            best_index = index
          end
        end
      end

      best_index
    end

    def segment_progress(start, finish, lon, lat)
      total_dx = finish[0] - start[0]
      total_dy = finish[1] - start[1]
      length_squared = (total_dx * total_dx) + (total_dy * total_dy)
      return 0 if length_squared.zero?

      ((lon - start[0]) * total_dx + (lat - start[1]) * total_dy) / length_squared
    end

    def align_stations_to_routes!(stations, route_features)
      line_strings = route_line_strings(route_features)
      return if line_strings.empty?

      stations.each do |station|
        next if station[:position_anchored]

        station[:lon], station[:lat] = TrackGeometry.align_point_to_lines(
          station[:lon],
          station[:lat],
          line_strings
        )
      end
    end

    alias snap_stations_to_routes! align_stations_to_routes!

    def nearest_point_on_line_strings(lon, lat, line_strings)
      TrackGeometry.nearest_on_line_strings(lon, lat, line_strings).first(2)
    end

    def project_point_on_segment(px, py, start, finish)
      x1, y1 = start
      x2, y2 = finish
      dx = x2 - x1
      dy = y2 - y1

      if dx.zero? && dy.zero?
        return [ x1, y1, haversine_meters(px, py, x1, y1) ]
      end

      t = [ [ ((px - x1) * dx + (py - y1) * dy) / ((dx * dx) + (dy * dy)), 0 ].max, 1 ].min
      proj_x = x1 + (t * dx)
      proj_y = y1 + (t * dy)

      [ proj_x, proj_y, haversine_meters(px, py, proj_x, proj_y) ]
    end

    def haversine_meters(lon1, lat1, lon2, lat2)
      earth_radius = 6_378_137.0
      lat1_rad = lat1 * Math::PI / 180
      lat2_rad = lat2 * Math::PI / 180
      delta_lat = (lat2 - lat1) * Math::PI / 180
      delta_lon = (lon2 - lon1) * Math::PI / 180

      a = Math.sin(delta_lat / 2)**2 +
          Math.cos(lat1_rad) * Math.cos(lat2_rad) * Math.sin(delta_lon / 2)**2

      2 * earth_radius * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
    end

    def tra_shared_junction_station?(ref)
      return false unless @line.system_id == "tra" && ref.present?

      numeric = canonical_tra_station_ref(ref)
      TraCatalog::BRANCH_JUNCTION_REFS.fetch(@line.slug, []).include?(numeric) ||
        TraCatalog::MAIN_LINE_JUNCTION_REFS.fetch(@line.slug, []).include?(numeric)
    end

    def station_features(stations)
      stations.filter_map do |station|
        next if station[:name].blank?

        original_ref = station[:ref].presence
        ref = original_ref
        transfer_entry = in_station_transfer_for(station[:name], ref: original_ref)
        if transfer_entry
          ref = TransitTransferCatalog.ref_for_line(transfer_entry.combined_ref, line: @line)
          if transfer_entry.lon && transfer_entry.lat
            station = station.merge(lon: transfer_entry.lon, lat: transfer_entry.lat)
          end
        end
        angle_station = station[:angle_station] || station[:name].match?(/轉角/)
        shared_junction = tra_shared_junction_station?(original_ref)

        {
          type: "Feature",
          properties: {
            feature_type: angle_station ? "angle_station" : "station",
            ref: ref,
            name: station[:name],
            line: station[:line] || @line.name,
            color: station[:color] || @line.color,
            segment: station[:segment],
            station_role: station[:station_role],
            note: station[:note],
            boarding_area: station[:boarding_area],
            passenger_service: station[:passenger_service],
            shared_junction: shared_junction || nil
          }.compact,
          geometry: {
            type: "Point",
            coordinates: [ station[:lon], station[:lat] ]
          }
        }
      end
    end
  end
end
