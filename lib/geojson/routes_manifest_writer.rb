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

    # Built separately from the main line (see AirportMrtExpressBuilder).
    EXTRA_MANIFEST_ENTRIES = {
      "new_taipei_metro" => [
        CIRCULAR_MANIFEST_ENTRY
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
          name: properties["name"].presence || data["name"].presence || properties["ref"],
          name_en: properties["name_en"].presence || name_en_from_bus_file(data),
          ref: properties["ref"],
          color: properties["color"].presence || color_from_bus_file(data)
        }
        %w[city_id operator_id operator operator_en official_map_url via].each do |key|
          entry[key.to_sym] = properties[key] if properties[key].present?
        end
        enrich_entry(entry, file_path, include_stations: false)
      rescue JSON::ParserError
        nil
      end
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

      station_names = station_names_for(file_path)
      entry[:station_names] = station_names if station_names.any?
      entry
    end

    def station_names_for(file_path)
      data = JSON.parse(File.read(file_path))
      names = []

      Array(data["features"]).each do |feature|
        next unless Transit::StationRef.passenger_station?(feature)

        properties = feature["properties"] || {}
        names << properties["name"].to_s.strip
        names << properties["name_en"].to_s.strip
        names << properties["ref"].to_s.strip
      end

      names.reject(&:empty?).uniq
    rescue JSON::ParserError, Errno::ENOENT
      []
    end
  end
end
