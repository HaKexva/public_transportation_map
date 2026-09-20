# frozen_string_literal: true

require "fileutils"
require "json"

module Geojson
  class BusReorganizer
    Result = Data.define(:moved, :skipped, :already_placed)

    def self.reorganize!(rewrite_manifest: true)
      new.reorganize!(rewrite_manifest: rewrite_manifest)
    end

    def reorganize!(rewrite_manifest: true)
      moved = []
      skipped = []
      already_placed = []

      Dir.glob(Geojson::BusLayout.bus_root.join("**/*.geojson")).sort.each do |path|
        pathname = Pathname.new(path)
        data = JSON.parse(pathname.read)
        properties = data["properties"] || {}
        slug = properties["id"].presence || pathname.basename(".geojson").to_s
        city_id = properties["city_id"].presence || Geojson::BusLayout.city_id_for_slug(slug)
        ref = properties["ref"]

        unless city_id
          skipped << "#{slug} (unknown city)"
          next
        end

        target = Geojson::BusLayout.geojson_path(
          city_id:,
          slug:,
          ref:,
          operator_id: properties["operator_id"],
          operator_name: properties["operator"]
        )
        next already_placed << slug if pathname == target

        if target.exist? && pathname != target
          # Canonical ASCII path already has the file (e.g. F/ → f/); drop the stray copy.
          FileUtils.rm(pathname)
          moved << "#{slug} (removed duplicate)"
          next
        end

        FileUtils.mkdir_p(target.dirname)
        FileUtils.mv(pathname, target)
        moved << slug
      rescue JSON::ParserError
        skipped << pathname.basename.to_s
      end

      prune_empty_dirs!
      Geojson::BusLayout.reset_route_counts!
      Geojson::RoutesManifestWriter.write! if rewrite_manifest && moved.any?
      Result.new(moved: moved, skipped: skipped, already_placed: already_placed)
    end

    private

    def prune_empty_dirs!
      Dir.glob(Geojson::BusLayout.bus_root.join("**/*")).reverse_each do |entry|
        next unless File.directory?(entry)

        Dir.children(entry).empty? && Dir.rmdir(entry)
      rescue SystemCallError
        nil
      end
    end
  end
end
