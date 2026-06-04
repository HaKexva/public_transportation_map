# frozen_string_literal: true

require "json"

module Geojson
  class AirportMrtExpressBuilder
    # A1–A13: terminal express; A18/A21 added for Huanbei-bound express (same track).
    EXPRESS_STOP_REFS = %w[A1 A3 A8 A12 A13 A18 A21].freeze

    COLOR = "#6A2C91"

    def self.build!
      new.build!
    end

    def initialize(source_path: Rails.root.join("public/geojson/taoyuan_metro/airport_mrt.geojson"))
      @source_path = source_path
    end

    def build!
      source = JSON.parse(@source_path.read)
      route_coords = extract_route_coords(source)
      stations_by_ref = extract_stations_by_ref(source)

      missing = EXPRESS_STOP_REFS.reject { |ref| stations_by_ref.key?(ref) }
      raise "Missing express stops in #{@source_path}: #{missing.join(', ')}" if missing.any?

      express_stations = EXPRESS_STOP_REFS.map { |ref| stations_by_ref.fetch(ref) }
      express_route_coords = build_express_route(route_coords, express_stations)

      collection = {
        type: "FeatureCollection",
        name: "機場捷運直達車",
        properties: {
          source: "Derived from #{@source_path.basename}. Express stops: #{EXPRESS_STOP_REFS.join(', ')}.",
          network: "桃園機場捷運",
          ref: "A",
          service_type: "express"
        },
        features: [
          express_route_feature(express_route_coords),
          *express_station_features(express_stations)
        ]
      }

      output_path = @source_path.dirname.join("airport_mrt_express.geojson")
      File.write(output_path, JSON.pretty_generate(collection))
      puts "Wrote #{output_path} (1 express route, #{express_stations.length} express stops)"
    end

    private

    def extract_route_coords(source)
      route = source.fetch("features").find { |feature| feature.dig("properties", "feature_type") == "route" }
      raise "No route geometry in #{@source_path}" unless route

      geometry = route.fetch("geometry")
      raise "Expected LineString route in #{@source_path}" unless geometry["type"] == "LineString"

      geometry.fetch("coordinates")
    end

    def extract_stations_by_ref(source)
      source.fetch("features").each_with_object({}) do |feature, index|
        next unless feature.dig("properties", "feature_type") == "station"

        ref_field = feature.dig("properties", "ref")
        coordinates = feature.dig("geometry", "coordinates")
        next if ref_field.blank? || coordinates.blank?

        refs = ref_field.to_s.split(";").map(&:strip).reject(&:blank?)
        airport_ref = refs.find { |entry| entry.start_with?("A") } || refs.first
        station = {
          ref: airport_ref,
          name: feature.dig("properties", "name"),
          coordinates: coordinates
        }

        refs.each { |entry| index[entry] = station }
      end
    end

    def build_express_route(route_coords, express_stations)
      indices = express_stations.map { |station| nearest_route_index(route_coords, station[:coordinates]) }
      indices.each_cons(2) do |start_index, end_index|
        raise "Express stops out of order along route" if end_index <= start_index
      end

      express_coords = []
      indices.each_with_index do |index, position|
        segment_start = indices[position]
        segment_end = indices[position + 1]
        break unless segment_end

        segment = route_coords[segment_start..segment_end]
        segment = segment.drop(1) if express_coords.any?
        express_coords.concat(segment)
      end

      express_coords
    end

    def nearest_route_index(route_coords, station_coord)
      station_lng, station_lat = station_coord

      route_coords.each_with_index.min_by do |coord, _index|
        distance_squared(coord[0], coord[1], station_lng, station_lat)
      end.last
    end

    def distance_squared(lng_a, lat_a, lng_b, lat_b)
      (lng_a - lng_b)**2 + (lat_a - lat_b)**2
    end

    def express_route_feature(coordinates)
      {
        type: "Feature",
        properties: {
          feature_type: "express_route",
          ref: "A",
          name: "機場捷運直達車",
          name_en: "Airport MRT Express",
          color: COLOR,
          service_type: "express"
        },
        geometry: {
          type: "LineString",
          coordinates: coordinates
        }
      }
    end

    def express_station_features(stations)
      stations.map do |station|
        {
          type: "Feature",
          properties: {
            feature_type: "station",
            ref: station[:ref],
            name: station[:name],
            line: "機場捷運直達車",
            color: COLOR,
            express_service: true
          },
          geometry: {
            type: "Point",
            coordinates: station[:coordinates]
          }
        }
      end
    end
  end
end
