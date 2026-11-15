# frozen_string_literal: true

require "json"

module Geojson
  class RoutesManifestWriter
    MANIFEST_PATH = Rails.root.join("public/geojson/routes.json")
    BUS_MANIFEST_PATH = Rails.root.join("public/geojson/bus/manifest.json")

    SYSTEMS = {
      "taipei_metro" => -> { Geojson::TaipeiMetroCatalog::LINES },
      "new_taipei_metro" => -> { Geojson::NewTaipeiMetroCatalog::LINES },
      "taoyuan_metro" => -> { Geojson::TaoyuanMetroCatalog::LINES },
      "taichung_metro" => -> { Geojson::TaichungMetroCatalog::LINES },
      "kaohsiung_metro" => -> { Geojson::KaohsiungMetroCatalog::LINES },
      "hsr" => -> { Geojson::HsrCatalog::LINES },
      "tra" => -> { Geojson::TraCatalog::LINES },
      "sugar_railway" => -> { Geojson::SugarRailwayCatalog::LINES },
      "ferry" => -> { Geojson::FerryCatalog::LINES },
      "other" => -> { Geojson::OtherTransitCatalog::LINES }
    }.freeze

    # Circular Line geojson lives under taipei_metro/ but is grouped with 新北捷運 in the UI.
    CIRCULAR_MANIFEST_ENTRY = {
      id: "circular",
      file: "/geojson/taipei_metro/circular.geojson",
      name: "環狀線",
      name_en: "Circular Line",
      ref: "Y",
      color: "#FEDB00"
    }.freeze

    # 安坑／三鶯 geojson lives under new_taipei_metro/ but lists under 台北捷運
    # after 藍線 (棕→紅→綠→橘→藍→安坑→三鶯→先導公車).
    ANKENG_MANIFEST_ENTRY = {
      id: "ankeng_lrt",
      file: "/geojson/new_taipei_metro/ankeng_lrt.geojson",
      name: "安坑輕軌",
      name_en: "Ankeng LRT",
      ref: "K",
      color: "#C3B091"
    }.freeze
    SANYING_MANIFEST_ENTRY = {
      id: "sanying_line",
      file: "/geojson/new_taipei_metro/sanying_line.geojson",
      name: "三鶯線",
      name_en: "Sanying Line",
      ref: "LB",
      color: "#6DB7D0"
    }.freeze
    # MRT pilot buses: keep under 台北捷運 after 三鶯. Omit city_id so selecting
    # them does not flip the UI into bus mode.
    TAIPEI_METRO_PILOT_BUS_ENTRIES = [
      {
        id: "new_taipei_985_xiandao_d20c01d95e",
        file: "/geojson/bus/taipei_new_taipei_bus/900-999/new_taipei_985_xiandao_d20c01d95e.geojson",
        name: "985萬大樹林先導公車",
        name_en: "985 Wanda–Shulin MRT Pilot Bus",
        ref: "985",
        color: "#16A34A"
      },
      {
        id: "new_taipei_629_xiandao_447f13f5ac",
        file: "/geojson/bus/taipei_new_taipei_bus/600-699/new_taipei_629_xiandao_447f13f5ac.geojson",
        name: "629汐東捷運先導公車",
        name_en: "629 Xidong MRT Pilot Bus",
        ref: "629",
        color: "#155e75"
      },
      {
        id: "new_taipei_lan_2_xiandao_03ad35aed7",
        file: "/geojson/bus/taipei_new_taipei_bus/lan/new_taipei_lan_2_xiandao_03ad35aed7.geojson",
        name: "藍海2線先導公車",
        name_en: "Blue Coast Line 2 Pilot Bus",
        ref: "藍海2",
        color: "#DC2626"
      }
    ].freeze

    # Built separately from the main line (see AirportMrtExpressBuilder / DanhaiSegmentWriter).
    EXTRA_MANIFEST_ENTRIES = {
      "taipei_metro" => [
        ANKENG_MANIFEST_ENTRY,
        SANYING_MANIFEST_ENTRY,
        *TAIPEI_METRO_PILOT_BUS_ENTRIES
      ],
      "new_taipei_metro" => [
        CIRCULAR_MANIFEST_ENTRY,
        {
          id: "danhai_lushan",
          file: "/geojson/new_taipei_metro/danhai_lushan.geojson",
          name: "綠山線",
          name_en: "Green Mountain Line",
          ref: "V",
          color: Geojson::NewTaipeiMetroCatalog::DANHAI_COLOR,
          branch_of: "danhai_lrt"
        },
        {
          id: "danhai_lanhai",
          file: "/geojson/new_taipei_metro/danhai_lanhai.geojson",
          name: "藍海線",
          name_en: "Blue Coast Line",
          ref: "V",
          color: Geojson::NewTaipeiMetroCatalog::DANHAI_COLOR,
          branch_of: "danhai_lrt"
        }
      ],
      "taoyuan_metro" => [
        {
          id: "airport_mrt_express",
          file: "/geojson/taoyuan_metro/airport_mrt_express.geojson",
          name: "機場捷運直達車",
          name_en: "Airport MRT Express",
          ref: "A",
          color: "#6A2C91",
          branch_of: "airport_mrt"
        }
      ]
    }.freeze

    # Combined build artifact; UI layers are danhai_lushan / danhai_lanhai.
    # 安坑／三鶯 are listed under taipei_metro instead.
    HIDDEN_MANIFEST_IDS = {
      "new_taipei_metro" => %w[danhai_lrt ankeng_lrt sanying_line]
    }.freeze

    def self.write!(path: MANIFEST_PATH, bus_path: :default)
      resolved_bus_path =
        case bus_path
        when :default
          path == MANIFEST_PATH ? BUS_MANIFEST_PATH : nil
        else
          bus_path
        end
      new(path: path, bus_path: resolved_bus_path).write!
    end

    def self.bus_entries(bus_path: BUS_MANIFEST_PATH)
      return [] unless bus_path.exist?

      payload = JSON.parse(bus_path.read)
      payload.is_a?(Hash) ? payload.fetch("bus", []) : Array(payload)
    rescue JSON::ParserError
      []
    end

    def initialize(path:, bus_path: BUS_MANIFEST_PATH)
      @path = path
      @bus_path = bus_path
    end

    def write!
      manifest = {}

      SYSTEMS.each do |system_id, loader|
        entries = Array(loader.call).filter_map { |line| manifest_entry(line) }
        entries.reject! { |entry| entry[:id] == "circular" } if system_id == "taipei_metro"
        hidden_ids = HIDDEN_MANIFEST_IDS[system_id] || []
        entries.reject! { |entry| hidden_ids.include?(entry[:id]) }
        extra = EXTRA_MANIFEST_ENTRIES[system_id] || []
        extra.each do |entry|
          next if entries.any? { |existing| existing[:id] == entry[:id] }

          path = Rails.root.join("public#{entry[:file]}")
          next unless path.exist?

          entries << enrich_entry(entry.dup, path)
        end
        manifest[system_id] = entries
      end

      if @bus_path
        bus_entries = bus_manifest_entries
        write_bus_manifest!(bus_entries)
        puts "Wrote #{@bus_path} (#{bus_entries.length} bus routes)" if bus_entries.any?
      end

      FileUtils.mkdir_p(@path.dirname)
      File.write(@path, JSON.pretty_generate(manifest))
      puts "Wrote #{@path} (#{manifest.values.sum(&:length)} rail routes)"
    end

    private

    def write_bus_manifest!(bus_entries)
      return if bus_entries.empty?

      FileUtils.mkdir_p(@bus_path.dirname)
      File.write(@bus_path, JSON.pretty_generate({ "bus" => bus_entries }))
    end

    def bus_manifest_entries
      bus_dir = Rails.root.join("public/geojson/bus")
      return [] unless bus_dir.exist?

      Dir.glob(bus_dir.join("**/*.geojson")).sort.filter_map do |path|
        file_path = Pathname.new(path)
        next if file_path.basename.to_s.start_with?("_")

        data = JSON.parse(File.read(file_path))
        properties = data["properties"] || {}
        relative = file_path.relative_path_from(Rails.root.join("public"))
        slug = properties["id"].presence || file_path.basename(".geojson").to_s

        entry = {
          id: slug,
          file: "/#{relative}",
          name: Geojson::BusServiceDays.display_name(
            properties["name"].presence || data["name"].presence || properties["ref"],
            properties["service_window"]
          ),
          name_en: Geojson::BusServiceDays.display_name_en(
            properties["name_en"].presence || name_en_from_bus_file(data),
            properties["service_window"]
          ),
          ref: properties["ref"],
          color: properties["color"].presence || color_from_bus_file(data)
        }
        entry[:color_2] = properties["color_2"] if properties["color_2"].present?
        %w[city_id operator_id operator operator_en operator_id_2 operator_2 operator_2_en official_map_url via via_en tdx_ref merged_refs off_days daily_trips detour_hours campus_span service_note service_note_en].each do |key|
          entry[key.to_sym] = properties[key] if properties[key].present?
        end
        entry[:loop] = true if properties["loop"]
        entry[:one_way] = true if one_way_bus?(data, properties)
        self.class.termini_for(data).each { |key, value| entry[key.to_sym] = value }
        enrich_entry(entry, file_path, include_stations: false)
      rescue JSON::ParserError
        nil
      end
    end

    # Outbound-only / inbound-only published shape (跳蛙、通勤…). Loops are not
    # one-way even when they only have a direction-0 ring.
    def one_way_bus?(data, properties)
      return false if properties["loop"]

      directions = Array(data["features"]).filter_map { |feature|
        next unless feature.dig("geometry", "type") == "LineString"

        feature.dig("properties", "direction")
      }.map { |direction| direction.to_s }.uniq
      directions.length == 1
    end

    # eBus/TDX 起迄站名 that differ from the published StopOfRoute ends
    # (574's board terminus is 信義國小; TDX still lists 板橋 like 573).
    TERMINI_OVERRIDES = {
      "new_taipei_574" => {
        "departure" => "信義國小",
        "destination" => "南天母廣場",
        "departure_en" => "Xinyi Elementary School",
        "destination_en" => "Nantianmu Square"
      }
    }.freeze

    # Outbound StopOfRoute poles first; Route 起迄 only for loops / when stops are missing.
    def self.termini_for(data)
      properties = data["properties"] || {}
      override = TERMINI_OVERRIDES[properties["id"].to_s]
      return override if override

      stations = Array(data["features"]).select { |feature| feature.dig("properties", "feature_type") == "station" }
      by_direction = stations.group_by { |feature| feature.dig("properties", "direction").to_s }
      chosen = by_direction["0"].presence || by_direction["1"]
      if chosen.present?
        first = chosen.first["properties"] || {}
        last = chosen.last["properties"] || {}
        from = first["name"].presence
        to = last["name"].presence
        if from.present? && to.present? && from != to
          return {
            "departure" => from,
            "destination" => to,
            "departure_en" => first["name_en"].presence,
            "destination_en" => last["name_en"].presence
          }.compact
        end
      end

      official_termini(properties)
    end

    def self.official_termini(properties)
      stored = {
        "departure" => properties["departure"].presence,
        "destination" => properties["destination"].presence,
        "departure_en" => properties["departure_en"].presence,
        "destination_en" => properties["destination_en"].presence
      }.compact
      return stored if stored["departure"].present? && stored["destination"].present?

      city_id = properties["city_id"].to_s
      ref = Geojson::BusImporter.schedule_ref(properties).presence || properties["ref"].to_s
      return stored if city_id.blank? || ref.blank? || !defined?(Transit::BusTdxSnapshot)

      route = Transit::BusTdxSnapshot.read(city_id, ref)&.dig("routes")&.find { |row|
        row["DepartureStopNameZh"].present? || row["DestinationStopNameZh"].present?
      } || Transit::BusTdxSnapshot.read(city_id, ref)&.dig("routes")&.first
      return stored unless route

      {
        "departure" => route["DepartureStopNameZh"].presence || stored["departure"],
        "destination" => route["DestinationStopNameZh"].presence || stored["destination"],
        "departure_en" => route["DepartureStopNameEn"].presence || stored["departure_en"],
        "destination_en" => route["DestinationStopNameEn"].presence || stored["destination_en"]
      }.compact
    end

    def name_en_from_bus_file(data)
      Array(data["features"]).find { |feature| feature.dig("properties", "feature_type") == "route" }
        &.dig("properties", "name_en")
    end

    def color_from_bus_file(data)
      Array(data["features"]).find { |feature| feature.dig("properties", "feature_type") == "route" }
        &.dig("properties", "color")
    end

    def manifest_entry(line)
      file_path = Rails.root.join("public/geojson", line.output_subdir, "#{line.slug}.geojson")
      return nil unless file_path.exist?

      entry = {
        id: line.slug,
        file: "/geojson/#{line.output_subdir}/#{line.slug}.geojson",
        name: line.name,
        name_en: line.name_en,
        ref: line.ref,
        color: line.color
      }

      entry[:branch_of] = line.branch_of if line.branch_of.present?
      enrich_entry(entry, file_path)
    end

    def enrich_entry(entry, file_path, include_stations: true)
      return entry unless include_stations

      data = JSON.parse(File.read(file_path))
      station_names = station_names_for(data)
      entry[:station_names] = station_names if station_names.any?
      bbox = bbox_for(data)
      entry[:bbox] = bbox if bbox
      entry
    rescue JSON::ParserError, Errno::ENOENT
      entry
    end

    # [min_lng, min_lat, max_lng, max_lat] so the map can pick nearby routes without loading every file.
    def bbox_for(data)
      lngs = []
      lats = []
      Array(data["features"]).each do |feature|
        each_position(feature.dig("geometry", "coordinates")) do |lng, lat|
          lngs << lng
          lats << lat
        end
      end
      return nil if lngs.empty?

      [ lngs.min, lats.min, lngs.max, lats.max ].map { |value| value.round(4) }
    end

    def each_position(coordinates, &block)
      return unless coordinates.is_a?(Array)

      if coordinates.first.is_a?(Numeric)
        yield coordinates[0].to_f, coordinates[1].to_f if coordinates.length >= 2
      else
        coordinates.each { |child| each_position(child, &block) }
      end
    end

    def station_names_for(data)
      names = []

      Array(data["features"]).each do |feature|
        next unless Transit::StationRef.passenger_station?(feature)

        properties = feature["properties"] || {}
        names << properties["name"].to_s.strip
        names << properties["name_en"].to_s.strip
        names << properties["ref"].to_s.strip
      end

      names.reject(&:empty?).uniq
    end
  end
end
