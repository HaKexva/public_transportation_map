# frozen_string_literal: true

require "json"

module Geojson
  class RoutesManifestWriter
    MANIFEST_PATH = Rails.root.join("public/geojson/routes.json")

    SYSTEMS = {
      "taipei_metro" => -> { Geojson::TaipeiMetroCatalog::LINES },
      "new_taipei_metro" => -> { Geojson::NewTaipeiMetroCatalog::LINES },
      "taoyuan_metro" => -> { Geojson::TaoyuanMetroCatalog::LINES },
      "taichung_metro" => -> { Geojson::TaichungMetroCatalog::LINES },
      "kaohsiung_metro" => -> { Geojson::KaohsiungMetroCatalog::LINES },
      "hsr" => -> { Geojson::HsrCatalog::LINES },
      "tra" => -> { Geojson::TraCatalog::LINES },
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

    def self.write!(path: MANIFEST_PATH)
      new(path: path).write!
    end

    def initialize(path:)
      @path = path
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
          entries << entry if path.exist?
        end
        manifest[system_id] = entries
      end

      FileUtils.mkdir_p(@path.dirname)
      File.write(@path, JSON.pretty_generate(manifest))
      puts "Wrote #{@path} (#{manifest.values.sum(&:length)} routes)"
    end

    private

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
      entry
    end
  end
end
