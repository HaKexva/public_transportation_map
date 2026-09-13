# frozen_string_literal: true

module Geojson
  # Shared StopUID / StationID / lat-lon cluster keys for bus stop indexes and depots.
  module BusStopClustering
    module_function

    def station_id_for(properties)
      properties = properties || {}
      properties["station_id"].presence || properties[:station_id].presence
    end

    def cluster_key(name:, lon:, lat:)
      return nil if name.blank? || lon.nil? || lat.nil?

      "#{format('%.4f', lat.to_f)}|#{format('%.4f', lon.to_f)}|#{name}"
    end

    def coordinates_for(feature)
      coords = feature.dig("geometry", "coordinates") || feature.dig(:geometry, :coordinates)
      return [ nil, nil ] unless coords.is_a?(Array) && coords.length >= 2

      [ coords[0].to_f, coords[1].to_f ]
    end

    def route_entry(properties)
      properties = properties || {}
      {
        "id" => properties["id"].presence || properties[:id],
        "ref" => properties["ref"].presence || properties[:ref],
        "name" => properties["name"].presence || properties[:name],
        "color" => properties["color"].presence || properties[:color]
      }.compact
    end

    def merge_route!(list, entry)
      return list if entry["id"].blank?

      existing = list.find { |row| row["id"] == entry["id"] }
      if existing
        existing.merge!(entry) { |_key, old, new| old.presence || new }
      else
        list << entry
      end
      list
    end
  end
end
