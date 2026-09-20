# frozen_string_literal: true

module Geojson
  # Merge fragmented MULTILINESTRING bus shapes and close circular loops so
  # turnaround depots are not drawn as disconnected gaps.
  module BusLoopCloser
    MERGE_GAP_METERS = 120.0
    CLOSE_GAP_METERS = 120.0

    module_function

    def process_collection!(data)
      return false unless data.is_a?(Hash)

      features = Array(data["features"])
      route_features = features.select { |feature| feature.dig("properties", "feature_type") == "route" }
      return false if route_features.empty?

      stations = features.select { |feature| feature.dig("properties", "feature_type") == "station" }
      changed = false

      grouped = route_features.group_by { |feature| feature.dig("properties", "direction").to_s }
      rebuilt_routes = []

      grouped.each_value do |group|
        lines = group.filter_map { |feature|
          coords = feature.dig("geometry", "coordinates")
          next unless feature.dig("geometry", "type") == "LineString" && Array(coords).length >= 2

          [ feature, coords ]
        }
        next if lines.empty?

        template = lines.first.first
        merged = merge_line_strings(lines.map(&:last))
        loop_stops = loop_stops_for_direction?(stations, template.dig("properties", "direction"))
        closed = close_loop_coordinates(merged, force: loop_stops)

        new_feature = {
          "type" => "Feature",
          "properties" => template["properties"].dup,
          "geometry" => {
            "type" => "LineString",
            "coordinates" => closed
          }
        }
        if loop_stops || nearly_closed?(closed)
          new_feature["properties"]["loop"] = true
        end

        changed ||= lines.length > 1 || closed.length != merged.length || nearly_closed?(closed) != nearly_closed?(merged)
        changed ||= !same_coordinates?(merged, closed)
        rebuilt_routes << new_feature
      end

      other = features.reject { |feature| feature.dig("properties", "feature_type") == "route" }
      data["features"] = rebuilt_routes + other
      if rebuilt_routes.any? { |feature| feature.dig("properties", "loop") }
        data["properties"] ||= {}
        data["properties"]["loop"] = true
        changed = true
      end
      changed
    end

    def merge_line_strings(lines)
      parts = Array(lines).map { |line| line.map { |point| point.map(&:to_f) } }.reject { |line| line.length < 2 }
      return [] if parts.empty?
      return parts.first if parts.length == 1

      remaining = parts.dup
      chain = remaining.shift.dup

      loop do
        best_index = nil
        best_gap = MERGE_GAP_METERS
        best_reversed = false
        best_prepend = false

        remaining.each_with_index do |part, index|
          candidates = [
            [ meters_between(chain.last, part.first), false, false ],
            [ meters_between(chain.last, part.last), true, false ],
            [ meters_between(chain.first, part.last), false, true ],
            [ meters_between(chain.first, part.first), true, true ]
          ]
          gap, reversed, prepend = candidates.min_by(&:first)
          next if gap > best_gap

          best_gap = gap
          best_index = index
          best_reversed = reversed
          best_prepend = prepend
        end

        break if best_index.nil?

        part = remaining.delete_at(best_index)
        part = part.reverse if best_reversed
        chain = best_prepend ? (part + chain) : (chain + part)
      end

      # Append leftover fragments (cannot chain cleanly) after the main run.
      remaining.each { |part| chain.concat(part) }
      chain
    end

    def close_loop_coordinates(coordinates, force: false)
      coords = Array(coordinates).map { |point| point.map(&:to_f) }
      return coords if coords.length < 3

      first = coords.first
      last = coords.last
      return coords if first == last

      gap = meters_between(first, last)
      return coords unless gap <= CLOSE_GAP_METERS
      return coords + [ first ] if force || nearly_closed?(coords)

      coords
    end

    def loop_stops_for_direction?(stations, direction)
      stops = Array(stations).select { |station|
        station.dig("properties", "direction").to_s == direction.to_s
      }
      stops = Array(stations) if stops.empty?
      return false if stops.length < 2

      ordered = stops.sort_by { |station|
        station.dig("properties", "sequence") ||
          station.dig("properties", "StopSequence") ||
          0
      }
      first = stop_key(ordered.first)
      last = stop_key(ordered.last)
      first.present? && first == last
    end

    def stop_key(station)
      props = station["properties"] || {}
      props["ref"].presence || props["station_id"].presence || props["name"].presence
    end

    def nearly_closed?(coordinates)
      coords = Array(coordinates)
      return false if coords.length < 4

      meters_between(coords.first, coords.last) <= CLOSE_GAP_METERS
    end

    def same_coordinates?(left, right)
      Array(left) == Array(right)
    end

    def meters_between(left, right)
      return Float::INFINITY if left.blank? || right.blank?

      dlon = (right[0] - left[0]) * 111_320 * Math.cos(left[1] * Math::PI / 180.0)
      dlat = (right[1] - left[1]) * 110_540
      Math.hypot(dlon, dlat)
    end
  end
end
