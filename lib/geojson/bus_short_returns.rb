# frozen_string_literal: true

require "digest"

module Geojson
  # Manual short-return variants that TDX does not publish as SubRoutes.
  # 531: two weekday trips turn back at 新明成功路口 instead of continuing to 紫雲里.
  module BusShortReturns
    ENTRIES = {
      "taipei_531" => {
        via: "返程至新明成功路口",
        via_en: "return to Xinming and Chenggong Intersection",
        direction: 1,
        end_stop: "新明成功路口",
        daily_trips: 2,
        off_days: %w[saturday sunday]
      }
    }.freeze
    END_SNAP_METERS = 80.0

    module_function

    def apply!(bus_root: Geojson::BusLayout.bus_root)
      ENTRIES.count do |route_id, entry|
        path = Geojson::BusLayout.find_geojson(route_id)
        next false unless path&.exist?

        split!(path, entry)
      end
    end

    def split!(path, entry)
      data = JSON.parse(File.read(path))
      properties = data["properties"] || {}
      return false if properties["via"].to_s == entry[:via]

      slug = "#{properties["id"]}_#{Digest::SHA1.hexdigest(entry[:via])[0, 10]}"
      out_path = File.join(File.dirname(path), "#{slug}.geojson")

      short = data.deep_dup
      return false unless clip_return!(short, entry)

      write_labels!(short, slug:, entry:)
      File.write(out_path, "#{JSON.pretty_generate(short)}\n")
      true
    end

    def clip_return!(data, entry)
      direction = entry[:direction].to_s
      end_stop = entry[:end_stop].to_s
      features = Array(data["features"])
      stop = features.find { |feature|
        feature.dig("geometry", "type") == "Point" &&
          feature.dig("properties", "direction").to_s == direction &&
          feature.dig("properties", "name").to_s == end_stop
      }
      return false unless stop

      tip = stop.dig("geometry", "coordinates")
      line_feature = features.find { |feature|
        feature.dig("geometry", "type") == "LineString" &&
          feature.dig("properties", "direction").to_s == direction
      }
      return false unless line_feature

      line = line_feature.dig("geometry", "coordinates")
      index = line.each_index.min_by { |i| meters(line[i], tip) }
      return false if index.nil? || meters(line[index], tip) > END_SNAP_METERS

      line_feature["geometry"]["coordinates"] = line[0..index]
      keep = true
      data["features"] = features.select do |feature|
        next true unless feature.dig("geometry", "type") == "Point"
        next true unless feature.dig("properties", "direction").to_s == direction

        if feature.dig("properties", "name").to_s == end_stop
          keep = false
          true
        else
          keep
        end
      end
      true
    end

    def write_labels!(data, slug:, entry:)
      properties = data["properties"]
      ref = properties["ref"]
      via = entry[:via]
      via_en = entry[:via_en]
      name = "#{ref}（#{via}）"
      name_en = "#{ref} (#{via_en})"
      data["id"] = slug if data.key?("id")
      data["name"] = name
      properties.merge!(
        "id" => slug,
        "name" => name,
        "name_en" => name_en,
        "via" => via,
        "via_en" => via_en,
        "daily_trips" => entry[:daily_trips]
      )
      properties["off_days"] = entry[:off_days] if entry[:off_days]
      data["features"].each do |feature|
        next unless feature["properties"]

        if feature.dig("geometry", "type") == "Point"
          feature["properties"]["line"] = name
        else
          feature["properties"]["name"] = name
          feature["properties"]["name_en"] = name_en
        end
      end
      data
    end

    def meters(a, b)
      Math.hypot((a[0] - b[0]) * 101_000, (a[1] - b[1]) * 111_000)
    end
  end
end
