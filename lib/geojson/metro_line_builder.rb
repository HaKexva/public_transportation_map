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

    def initialize(line)
      @line = line
    end

    def build!
      route_features = build_route_features

      raise "No track geometry for #{@line.slug}" if route_features.empty?

      extend_routes_for_depots!(route_features)

      stations = fetch_stations_for_line
      apply_taichung_station_coordinates!(stations) if @line.system_id == "taichung_metro"
      align_stations_to_routes!(stations, route_features)

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

    def build_route_features
      return build_skytrain_route_features if @line.slug == "taoyuan_airport_skytrain"
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
      role = danhai_terminal_role(station[:ref], segment)

      station.merge(
        segment: segment,
        color: danhai_segment_color(segment),
        line: "淡海輕軌（#{line_label}）",
        station_role: role
      ).compact
    end

    def danhai_terminal_role(ref, segment)
      return "origin" if ref == NewTaipeiMetroCatalog::DANHAI_SHARED_ORIGIN_REF

      case segment
      when "lushan"
        "destination" if ref == NewTaipeiMetroCatalog::DANHAI_LUSHAN_DESTINATION_REF
      when "lanhai"
        "destination" if ref == NewTaipeiMetroCatalog::DANHAI_LANHAI_DESTINATION_REF
      end
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

    def in_station_transfer_for(name)
      TaipeiMetroCatalog::IN_STATION_TRANSFERS_BY_NAME[name] ||
        KaohsiungMetroCatalog::IN_STATION_TRANSFERS_BY_NAME[name] ||
        KaohsiungMetroCatalog::CIRCULAR_LRT_IN_STATION_TRANSFERS_BY_NAME[name]
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

    def station_features(stations)
      stations.filter_map do |station|
        next if station[:name].blank?

        transfer = in_station_transfer_for(station[:name])
        ref = transfer&.fetch(:combined_ref) || station[:ref]
        if transfer
          station = station.merge(lon: transfer[:lon], lat: transfer[:lat])
        end
        angle_station = station[:angle_station] || station[:name].match?(/轉角/)

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
            passenger_service: station[:passenger_service]
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
