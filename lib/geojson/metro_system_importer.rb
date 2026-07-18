# frozen_string_literal: true

module Geojson
  class MetroSystemImporter
    MANIFEST_PATH = Rails.root.join("public/geojson/routes.json")

    def self.import!(system_id:, lines:)
      new(system_id: system_id, lines: lines).import!
    end

    def initialize(system_id:, lines:)
      @system_id = system_id
      @lines = lines
    end

    def import!
      Geojson::MetroLineBuilder.reset_tra_station_cache! if @system_id == "tra"

      built_lines = []

      @lines.each do |line|
        output_dir = Rails.root.join("public/geojson", line.output_subdir)
        FileUtils.mkdir_p(output_dir)

        MetroLineBuilder.build!(line)
        built_lines << manifest_entry(line)
        sleep 2
      rescue StandardError => error
        warn "Skipped #{line.slug}: #{error.message}"
      end

      if built_lines.any?
        Geojson::RoutesManifestWriter.write!
        puts "Updated routes manifest with #{built_lines.length} rebuilt #{@system_id} lines"
      else
        warn "No #{@system_id} lines built; leaving routes manifest unchanged"
      end
    end

    private

    def manifest_entry(line)
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

    def write_manifest!(system_id, built_lines)
      manifest = JSON.parse(File.read(MANIFEST_PATH))
      manifest[system_id] = built_lines
      File.write(MANIFEST_PATH, JSON.pretty_generate(manifest))
    end
  end
end
