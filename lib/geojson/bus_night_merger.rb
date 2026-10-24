# frozen_string_literal: true

module Geojson
  # 夜間公車 (e.g. 39夜) published as its own TDX route but running exactly the
  # day route's stops and path is folded into the day route: the night file is
  # removed and its ref kept in the day route's `merged_refs` (for timetables).
  module BusNightMerger
    NIGHT_REF = /\A(.+?)\s*夜\z/
    MAX_PATH_OFFSET_METERS = 50.0

    module_function

    def process_city_dir!(dir)
      paths = Dir[File.join(dir.to_s, "**", "*.geojson")]
      collections = paths.filter_map do |path|
        data = JSON.parse(File.read(path))
        [ path, data ] if data.is_a?(Hash)
      rescue JSON::ParserError
        nil
      end
      by_ref = collections.group_by { |_, data| data.dig("properties", "ref").to_s }

      merged = []
      collections.each do |night_path, night|
        base = night.dig("properties", "ref").to_s[NIGHT_REF, 1]
        next unless base

        city = night.dig("properties", "city_id")
        day_path, day = Array(by_ref[base]).find { |_, data|
          data.dig("properties", "via").blank? && data.dig("properties", "city_id") == city
        }
        next unless day && same_service?(day, night)

        refs = Array(day.dig("properties", "merged_refs"))
        day["properties"]["merged_refs"] = (refs + [ night.dig("properties", "ref") ]).uniq
        File.write(day_path, "#{JSON.pretty_generate(day)}\n")
        File.delete(night_path)
        merged << File.basename(night_path, ".geojson")
      end
      merged
    end

    def same_service?(day, night)
      [ 0, 1 ].all? do |direction|
        stop_names(day, direction) == stop_names(night, direction) &&
          path_within?(route_line(night, direction), route_line(day, direction))
      end
    end

    def stop_names(data, direction)
      features(data, "station", direction).map { |feature| feature.dig("properties", "name") }
    end

    def route_line(data, direction)
      features(data, "route", direction).first&.dig("geometry", "coordinates")
    end

    def path_within?(line, reference)
      return line.nil? && reference.nil? if line.nil? || reference.nil?

      line.all? do |point|
        reference.each_cons(2).any? { |a, b| Geojson::BusShapeTrimmer.project(point, a, b)[:distance] <= MAX_PATH_OFFSET_METERS }
      end
    end

    def features(data, type, direction)
      Array(data["features"]).select { |feature|
        feature.dig("properties", "feature_type") == type && feature.dig("properties", "direction").to_s == direction.to_s
      }
    end
  end
end
