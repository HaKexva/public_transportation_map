# frozen_string_literal: true

module Geojson
  # Squashes short diagonal / filleted intersection cuts into an approach that
  # runs to the junction, then turns on a small circular arc (not a diagonal cut
  # and not a razor-sharp L), so overlapping bus lines stay readable.
  class BusShapeSharpener
    MIN_TURN_DEG = 55.0
    MAX_TURN_DEG = 130.0
    MAX_SPAN_M = 90.0
    MIN_LEG_M = 3.0
    MIN_SEGMENT_M = 0.5
    MIN_CUT_DEPTH_M = 1.5
    FILLET_RADIUS_M = 12.0
    FILLET_LEG_FRACTION = 0.35
    MIN_FILLET_RADIUS_M = 2.0
    ARC_SAMPLES = 6

    def self.sharpen(coordinates)
      new.sharpen(coordinates)
    end

    def sharpen(coordinates)
      line = Array(coordinates).map { |point| [ point[0].to_f, point[1].to_f ] }
      line = drop_short_segments(line)
      return line if line.length < 3

      output = [ line.first ]
      index = 1

      while index < line.length - 1
        window = best_corner_window(line, index)
        if window
          start_i, end_i = window
          corner = miter_corner(line[start_i - 1], line[start_i], line[end_i], line[end_i + 1])

          if corner && finite_point?(corner)
            inbound_origin = line[start_i - 1]
            outbound_exit = line[end_i + 1]
            fillet_points(
              corner,
              inbound_origin,
              outbound_exit
            ).each do |point|
              output << point unless same_point?(output.last, point)
            end
            index = end_i + 1
            next
          end
        end

        output << line[index] unless same_point?(output.last, line[index])
        index += 1
      end

      output << line.last unless same_point?(output.last, line.last)
      output
    end

    private

    def best_corner_window(line, start_i)
      return nil if start_i < 1 || start_i >= line.length - 1
      return nil if segment_length_m(line[start_i - 1], line[start_i]) < MIN_LEG_M

      inbound_bearing = bearing_degrees(line[start_i - 1], line[start_i])
      best = nil

      (start_i...(line.length - 1)).each do |end_i|
        fillet_span = path_length_m(line, start_i, end_i)
        break if fillet_span > MAX_SPAN_M
        next if segment_length_m(line[end_i], line[end_i + 1]) < MIN_LEG_M

        outbound_bearing = bearing_degrees(line[end_i], line[end_i + 1])
        turn = signed_turn_degrees(inbound_bearing, outbound_bearing).abs
        next unless turn.between?(MIN_TURN_DEG, MAX_TURN_DEG)

        corner = miter_corner(line[start_i - 1], line[start_i], line[end_i], line[end_i + 1])
        next unless corner && finite_point?(corner)

        cut_depth = fillet_depth_m(line, start_i, end_i, corner)
        # Already a crisp single vertex near 90° with almost no cut — leave it.
        next if end_i == start_i && cut_depth < MIN_CUT_DEPTH_M && turn.between?(80.0, 100.0)
        # Require a meaningful cut for multi-vertex fillets, or a clear soft single bend.
        next if cut_depth < MIN_CUT_DEPTH_M && end_i > start_i
        next if cut_depth < MIN_CUT_DEPTH_M && turn < 70.0

        score = turn + (cut_depth * 2.0) - (fillet_span * 0.15)
        if best.nil? || score > best[:score]
          best = { start_i:, end_i:, score: }
        end
      end

      return nil unless best

      [ best[:start_i], best[:end_i] ]
    end

    def fillet_points(corner, inbound_origin, outbound_exit)
      inbound_bearing = bearing_degrees(inbound_origin, corner)
      outbound_bearing = bearing_degrees(corner, outbound_exit)
      turn = signed_turn_degrees(inbound_bearing, outbound_bearing)
      return [ corner ] if turn.abs < 1.0

      inbound_leg = meters_between(inbound_origin, corner)
      outbound_leg = meters_between(corner, outbound_exit)
      radius = [
        FILLET_RADIUS_M,
        inbound_leg * FILLET_LEG_FRACTION,
        outbound_leg * FILLET_LEG_FRACTION
      ].min

      return [ corner ] if radius < MIN_FILLET_RADIUS_M

      half_turn_rad = (turn.abs * Math::PI / 180.0) / 2.0
      tangent_distance = radius * Math.tan(half_turn_rad)
      return [ corner ] if tangent_distance < MIN_FILLET_RADIUS_M * 0.5
      return [ corner ] if tangent_distance > inbound_leg * 0.9 || tangent_distance > outbound_leg * 0.9

      pin = offset_point(corner, reverse_bearing(inbound_bearing), tangent_distance)
      pout = offset_point(corner, outbound_bearing, tangent_distance)

      inside_bearing = inbound_bearing + (turn.positive? ? 90.0 : -90.0)
      center = offset_point(pin, inside_bearing, radius)

      start_angle = bearing_degrees(center, pin)
      end_angle = bearing_degrees(center, pout)
      sweep = signed_turn_degrees(start_angle, end_angle)
      # Prefer the short sweep matching the road turn direction.
      if turn.positive? && sweep.negative?
        sweep += 360.0
      elsif turn.negative? && sweep.positive?
        sweep -= 360.0
      end

      samples = [ pin ]
      (1...ARC_SAMPLES).each do |step|
        t = step.to_f / ARC_SAMPLES
        angle = start_angle + (sweep * t)
        samples << offset_point(center, angle, radius)
      end
      samples << pout
      samples
    end

    def fillet_depth_m(line, start_i, end_i, corner)
      (start_i..end_i).map { |index| meters_between(line[index], corner) }.max || 0.0
    end

    def path_length_m(line, from_i, to_i)
      return 0.0 if to_i <= from_i

      (from_i...to_i).sum { |index| segment_length_m(line[index], line[index + 1]) }
    end

    def miter_corner(inbound_origin, inbound_next, outbound_prev, outbound_exit)
      inbound_bearing = bearing_degrees(inbound_origin, inbound_next)
      outbound_bearing = bearing_degrees(outbound_prev, outbound_exit)
      # Extend approach forward from inbound_next; extend exit backward from outbound_prev.
      intersect_bearings(inbound_next, inbound_bearing, outbound_prev, reverse_bearing(outbound_bearing))
    end

    def intersect_bearings(origin_a, bearing_a, origin_b, bearing_b)
      lat0 = (origin_a[1] + origin_b[1]) / 2.0
      ax, ay = to_local_meters(origin_a, lat0)
      bx, by = to_local_meters(origin_b, lat0)
      adx, ady = bearing_to_local_delta(bearing_a)
      bdx, bdy = bearing_to_local_delta(bearing_b)

      denom = (adx * bdy) - (ady * bdx)
      return nil if denom.abs < 1e-9

      t = (((bx - ax) * bdy) - ((by - ay) * bdx)) / denom
      u = (((bx - ax) * ady) - ((by - ay) * adx)) / denom
      return nil if t < -5.0 || t > 120.0
      return nil if u < -5.0 || u > 120.0

      from_local_meters(ax + (adx * t), ay + (ady * t), lat0)
    end

    def bearing_to_local_delta(bearing_deg)
      radians = bearing_deg * Math::PI / 180.0
      [ Math.sin(radians), Math.cos(radians) ]
    end

    def to_local_meters(point, lat0)
      lon, lat = point
      [
        lon * 111_320 * Math.cos(lat0 * Math::PI / 180.0),
        lat * 110_540
      ]
    end

    def from_local_meters(x, y, lat0)
      [
        x / (111_320 * Math.cos(lat0 * Math::PI / 180.0)),
        y / 110_540
      ]
    end

    def offset_point(origin, bearing_deg, distance_m)
      lat0 = origin[1]
      dx, dy = bearing_to_local_delta(bearing_deg)
      x, y = to_local_meters(origin, lat0)
      from_local_meters(x + (dx * distance_m), y + (dy * distance_m), lat0)
    end

    def drop_short_segments(line)
      return line if line.length < 2

      compact = [ line.first ]
      line.drop(1).each do |point|
        next if segment_length_m(compact.last, point) < MIN_SEGMENT_M

        compact << point
      end
      compact << line.last unless same_point?(compact.last, line.last)
      compact
    end

    def segment_length_m(left, right)
      meters_between(left, right)
    end

    def meters_between(left, right)
      dlon = (right[0] - left[0]) * 111_320 * Math.cos(left[1] * Math::PI / 180.0)
      dlat = (right[1] - left[1]) * 110_540
      Math.hypot(dlon, dlat)
    end

    def bearing_degrees(from, to)
      dlon = (to[0] - from[0]) * Math.cos(from[1] * Math::PI / 180.0)
      dlat = to[1] - from[1]
      Math.atan2(dlon, dlat) * 180.0 / Math::PI
    end

    def reverse_bearing(bearing_deg)
      bearing_deg + 180.0
    end

    def signed_turn_degrees(inbound, outbound)
      delta = outbound - inbound
      delta -= 360.0 while delta > 180.0
      delta += 360.0 while delta < -180.0
      delta
    end

    def same_point?(left, right, epsilon = 1e-9)
      return false if left.nil? || right.nil?

      (left[0] - right[0]).abs < epsilon && (left[1] - right[1]).abs < epsilon
    end

    def finite_point?(point)
      point.is_a?(Array) && point.size >= 2 && point[0].finite? && point[1].finite?
    end
  end
end
