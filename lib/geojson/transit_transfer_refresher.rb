# frozen_string_literal: true

module Geojson
  module TransitTransferRefresher
    SYSTEM_LINES = {
      "taipei_metro" => TaipeiMetroCatalog::LINES,
      "new_taipei_metro" => NewTaipeiMetroCatalog::LINES,
      "taoyuan_metro" => TaoyuanMetroCatalog::LINES,
      "taichung_metro" => TaichungMetroCatalog::LINES,
      "kaohsiung_metro" => KaohsiungMetroCatalog::LINES,
      "hsr" => HsrCatalog::LINES,
      "other" => OtherTransitCatalog::LINES
    }.freeze

    class << self
      def refresh!
        updated_files = []

        SYSTEM_LINES.each do |system_id, lines|
          lines.each do |line|
            path = geojson_path(system_id, line.slug)
            next unless path.exist?

            count = refresh_file!(path, line)
            next if count.zero?

            updated_files << "#{path.relative_path_from(Rails.root)} (#{count} stations)"
          end
        end

        updated_files
      end

      private

      def geojson_path(system_id, slug)
        Rails.public_path.join("geojson/#{system_id}/#{slug}.geojson")
      end

      def refresh_file!(path, line)
        data = JSON.parse(path.read)
        updated = 0

        data["features"].each do |feature|
          next unless feature.dig("properties", "feature_type") == "station"

          name = feature.dig("properties", "name")
          ref = feature.dig("properties", "ref")
          entry = transfer_entry_for(name, line: line, ref: ref)
          next unless entry

          feature["properties"]["ref"] = entry.combined_ref
          coords = TransitTransferCatalog.coordinates_for_line(
            entry,
            line: line,
            ref: TransitTransferCatalog.ref_for_line(entry.combined_ref, line: line)
          )
          if coords[:lon] && coords[:lat]
            feature["geometry"]["coordinates"] = [ coords[:lon], coords[:lat] ]
          end
          updated += 1
        end

        path.write(JSON.pretty_generate(data)) if updated.positive?
        updated
      end

      def transfer_entry_for(name, line:, ref: nil)
        if line.system_id.in?(%w[taipei_metro kaohsiung_metro])
          legacy = legacy_transfer_for(name, line: line)
          return legacy if legacy
        end

        TransitTransferCatalog.transfer_for(name, line: line, ref: ref)
      end

      def legacy_transfer_for(name, line:)
        legacy = TaipeiMetroCatalog::IN_STATION_TRANSFERS_BY_NAME[name] ||
          KaohsiungMetroCatalog::IN_STATION_TRANSFERS_BY_NAME[name] ||
          KaohsiungMetroCatalog::CIRCULAR_LRT_IN_STATION_TRANSFERS_BY_NAME[name] ||
          KaohsiungMetroCatalog::CROSS_ROUTE_TRANSFERS_BY_NAME[name]
        return nil unless legacy
        return nil unless legacy_transfer_applies_to_line?(legacy, line)

        TransitTransferCatalog::Entry.new(
          combined_ref: legacy[:combined_ref],
          lon: legacy[:lon],
          lat: legacy[:lat],
          coordinates_by_ref: legacy[:coordinates_by_ref]
        )
      end

      def legacy_transfer_applies_to_line?(transfer, line)
        lines = transfer[:lines]
        lines.nil? || lines.empty? || lines.include?(line.slug)
      end
    end
  end
end
