# frozen_string_literal: true

module Geojson
  # TDX traces winding roads with sparse vertices, so a smooth mountain road
  # renders as a chain of kinks. Replace every corner with a circular arc,
  # bounded two ways so it never over-rounds:
  # - the arc starts and ends within LEG_FRACTION of each neighbouring leg,
  #   so arcs on consecutive corners never overlap;
  # - the arc stays within MAX_DEVIATION_M of the original corner, so a
  #   junction turn only gets a tight curve and the line never leaves the road.
  module BusCornerRounder
    MAX_DEVIATION_M = 6.0
    LEG_FRACTION = 0.5
    MIN_TURN_DEG = 3.0
    # Near-reversals are terminal turnarounds; rounding would bulge them out.
    MAX_TURN_DEG = 170.0
    # Shorter arcs are under a pixel even at street zoom.
    MIN_TANGENT_M = 2.0
    ARC_STEP_DEG = 15.0
    MAX_ARC_POINTS = 9
    MARKER = "corners_rounded"

    module_function

    # Rounds each route LineString once (marked so re-runs leave it alone).
    def process_collection!(data)
      return false unless data.is_a?(Hash)

      changed = false
      Array(data["features"]).each do |feature|
        properties = feature["properties"] ||= {}
        next unless properties["feature_type"] == "route" && feature.dig("geometry", "type") == "LineString"
        next if properties[MARKER]

        feature["geometry"]["coordinates"] = round_line(feature["geometry"]["coordinates"])
        properties[MARKER] = true
        changed = true
      end
      changed
    end

    def round_line(line)
      return line if !line.is_a?(Array) || line.length < 3

      lon0, lat0 = line.first
      kx = 111_320.0 * Math.cos(lat0 * Math::PI / 180)
      ky = 110_540.0
      xy = line.map { |lon, lat| [ (lon - lon0) * kx, (lat - lat0) * ky ] }
      to_lonlat = ->((x, y)) { [ (lon0 + (x / kx)).round(7), (lat0 + (y / ky)).round(7) ] }

      result = [ line.first ]
      (1...(line.length - 1)).each do |index|
        arc = corner_arc(xy[index - 1], xy[index], xy[index + 1])
        if arc
          result.concat(arc.map(&to_lonlat))
        else
          result << line[index]
        end
      end
      result << line.last
      result.chunk_while { |a, b| a == b }.map(&:first)
    end

    def corner_arc(previous, corner, following)
      in_x = corner[0] - previous[0]
      in_y = corner[1] - previous[1]
      out_x = following[0] - corner[0]
      out_y = following[1] - corner[1]
      in_length = Math.hypot(in_x, in_y)
      out_length = Math.hypot(out_x, out_y)
      return nil if in_length < MIN_TANGENT_M || out_length < MIN_TANGENT_M

      in_x /= in_length
      in_y /= in_length
      out_x /= out_length
      out_y /= out_length
      cross = (in_x * out_y) - (in_y * out_x)
      turn = Math.atan2(cross.abs, (in_x * out_x) + (in_y * out_y))
      turn_deg = turn * 180 / Math::PI
      return nil if turn_deg < MIN_TURN_DEG || turn_deg > MAX_TURN_DEG

      half = turn / 2
      radius_by_deviation = MAX_DEVIATION_M / ((1 / Math.cos(half)) - 1)
      radius_by_legs = LEG_FRACTION * [ in_length, out_length ].min / Math.tan(half)
      radius = [ radius_by_deviation, radius_by_legs ].min
      tangent = radius * Math.tan(half)
      return nil if tangent < MIN_TANGENT_M

      side = cross.positive? ? 1 : -1
      start = [ corner[0] - (in_x * tangent), corner[1] - (in_y * tangent) ]
      center = [ start[0] - (in_y * radius * side), start[1] + (in_x * radius * side) ]
      start_angle = Math.atan2(start[1] - center[1], start[0] - center[0])
      steps = (turn_deg / ARC_STEP_DEG).ceil.clamp(1, MAX_ARC_POINTS - 1)

      (0..steps).map do |step|
        angle = start_angle + (side * turn * step / steps)
        [ center[0] + (radius * Math.cos(angle)), center[1] + (radius * Math.sin(angle)) ]
      end
    end
  end
end
