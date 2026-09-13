# frozen_string_literal: true

require "fileutils"
require "json"

module Geojson
  class BusManualImporter
    INBOX = Rails.root.join("inbox/bus_manual")
    MANIFEST = INBOX.join("manifest.csv")
    ANNOTATIONS = Rails.root.join("docs/bus_data_gaps/missing_official_maps.md")

    Result = Data.define(:updated_slugs, :skipped, :imported_geometry)

    def self.import!(rewrite_manifest: true)
      new.import!(rewrite_manifest: rewrite_manifest)
    end

    def import!(rewrite_manifest: true)
      updated = []
      skipped = []
      imported_geometry = []

      import_manifest_rows(updated:, skipped:, imported_geometry:)
      import_markdown_annotations(updated:, skipped:)

      Geojson::RoutesManifestWriter.write! if rewrite_manifest && (updated.any? || imported_geometry.any?)
      Result.new(updated_slugs: updated.uniq, skipped: skipped, imported_geometry: imported_geometry)
    end

    private

    def import_manifest_rows(updated:, skipped:, imported_geometry:)
      return unless MANIFEST.exist?

      rows = MANIFEST.read.lines.map(&:strip).reject(&:empty?)
      return if rows.length <= 1

      headers = rows.first.split(",")
      rows.drop(1).each do |line|
        row = headers.zip(line.split(",")).to_h
        slug = row["slug"].to_s.strip
        next if slug.blank?

        if row["geometry_file"].to_s.strip.present?
          imported = import_geometry_row!(row)
          if imported
            imported_geometry << slug
            updated << slug
          else
            skipped << "#{slug} (geometry missing)"
          end
        end

        map = row["map_file_or_url"].to_s.strip
        next if map.blank?

        if map.match?(/\Ahttps?:\/\//i)
          apply_official_map!(slug, map) ? updated << slug : skipped << "#{slug} (geojson not found for URL)"
        else
          copied = import_map_file!(slug, row["city_id"], map)
          if copied
            updated << slug
          else
            skipped << "#{slug} (map file missing: #{map})"
          end
        end
      end
    end

    def import_markdown_annotations(updated:, skipped:)
      return unless ANNOTATIONS.exist?

      ANNOTATIONS.read.each_line do |line|
        next unless (match = line.match(/\(`([^`]+)`\).+<-\s*(https?:\/\/\S+)/))

        slug = match[1]
        url = match[2].strip
        apply_official_map!(slug, url) ? updated << slug : skipped << "#{slug} (geojson not found for annotation)"
      end
    end

    def import_geometry_row!(row)
      slug = row["slug"].to_s.strip
      city_id = row["city_id"].to_s.strip
      source = resolve_inbox_path(row["geometry_file"])
      return false unless source&.exist?

      target = Geojson::BusLayout.geojson_path(city_id:, slug:, ref: row["ref"])
      FileUtils.mkdir_p(target.dirname)
      FileUtils.cp(source, target)
      true
    end

    def import_map_file!(slug, city_id, map_path)
      source = resolve_inbox_path(map_path)
      return false unless source&.exist?

      maps_dir = Geojson::BusLayout.maps_dir(city_id:)
      FileUtils.mkdir_p(maps_dir)
      target = maps_dir.join("#{slug}#{source.extname}")
      FileUtils.cp(source, target)
      apply_official_map!(slug, Geojson::BusLayout.public_url(target))
    end

    def apply_official_map!(slug, url)
      path = Geojson::BusLayout.find_geojson(slug)
      return false unless path&.exist?

      data = JSON.parse(path.read)
      properties = data["properties"] ||= {}
      properties["id"] ||= slug
      properties["official_map_url"] = url
      path.write("#{JSON.pretty_generate(data)}\n")
      true
    rescue JSON::ParserError
      false
    end

    def resolve_inbox_path(relative)
      return if relative.blank?

      candidate = INBOX.join(relative)
      return candidate if candidate.exist?

      Pathname.new(relative) if Pathname.new(relative).exist?
    end
  end
end
