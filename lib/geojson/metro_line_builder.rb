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

      stations = fetch_stations_for_line
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

      route_features = []

      @line.relation_ids.each_with_index do |relation_id, relation_index|
        ways = OsmRouteExtractor.new(relation_id: relation_id).fetch_way_elements
        next if ways.empty?

        OsmRouteExtractor.new(relation_id: relation_id).stitch_line_strings(ways).each_with_index do |coordinates, index|
          route_features << route_feature(coordinates, branch_index: index, relation_index: relation_index)
        end
      end

      @line.way_ids.each_with_index do |way_id, way_index|
        ways = OsmRouteExtractor.fetch_way_elements(way_id)
        next if ways.empty?

        stitcher = OsmRouteExtractor.new(relation_id: @line.relation_ids.first || 0)
        stitcher.stitch_line_strings(ways).each_with_index do |coordinates, index|
          route_features << route_feature(coordinates, branch_index: index, relation_index: way_index)
        end
      end

      route_features
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

    def fetch_maokong_gondola_stations
      stations = @line.way_ids.flat_map do |way_id|
        OsmRouteExtractor.fetch_aerialway_stations_for_way(
          way_id,
          ref_prefix: @line.station_ref_prefix,
          include_angle_stations: true
        )
      end

      merge_stations([], stations.map { |station| enrich_maokong_station(station) })
        .sort_by { |station| maokong_station_sort_key(station[:ref]) }
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
      prefix = ref[/\A[A-Z]+/] || ref
      numeric = ref[/\d+/]
      suffix = ref.sub(/\A#{Regexp.escape(prefix)}#{numeric}/, "")

      [ prefix, numeric.to_i, suffix ]
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

      name = @line.name
      name = "#{name} (#{branch_index + 1})" if @line.relation_ids.length > 1

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
      match = ref.to_s.match(/V(\d+)/i)
      match ? match[1].to_i : 99
    end

    def danhai_segment_key(relation_index)
      return nil unless @line.slug == "danhai_lrt"

      %w[lushan lanhai][relation_index]
    end

    def danhai_segment_color(_segment)
      @line.color if @line.slug == "danhai_lrt"
    end

    def station_features(stations)
      stations.filter_map do |station|
        next if station[:name].blank?

        transfer = TaipeiMetroCatalog::IN_STATION_TRANSFERS_BY_NAME[station[:name]]
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
