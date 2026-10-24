# frozen_string_literal: true

module Geojson
  # TDX often joins the two directions at a point past the return trip's first
  # stop: the outbound line overshoots that stop and the return line starts
  # beyond it. Hand the overshoot to the return line so the outbound ends at
  # the stop where the return trip begins (the drawn streets do not change).
  # Turnarounds the return line itself drives back through are left alone.
  module BusTerminusHandoff
    JOIN_METERS = 5.0
    STOP_OFFSET_METERS = 25.0
    MIN_OVERSHOOT_METERS = 10.0
    MAX_OVERSHOOT_METERS = 120.0
    RETURN_HEAD_METERS = 150.0
    JOIN_CLUSTER_METERS = 5.0
    MAX_JOIN_KINK_METERS = 8.0

    module_function

    def process_collection!(data)
      return false unless data.is_a?(Hash)

      features = Array(data["features"])
      lines = features.select { |feature| feature.dig("properties", "feature_type") == "route" && feature.dig("geometry", "type") == "LineString" }
      stations = features.select { |feature| feature.dig("properties", "feature_type") == "station" }
      by_direction = lines.group_by { |feature| feature.dig("properties", "direction").to_i }
      return false unless by_direction.keys.sort == [ 0, 1 ] && by_direction.values.all? { |group| group.size == 1 }

      stops = ->(direction) { stations.select { |station| station.dig("properties", "direction").to_i == direction } }
      changed = handoff!(by_direction[0].first, by_direction[1].first, stops[0].last, stops[1].first)
      changed | handoff!(by_direction[1].first, by_direction[0].first, stops[1].last, stops[0].first)
    end

    def handoff!(arriving, departing, arriving_stop, departing_stop)
      inbound = arriving.dig("geometry", "coordinates")
      outbound = departing.dig("geometry", "coordinates")
      stop = departing_stop&.dig("geometry", "coordinates")
      last_stop = arriving_stop&.dig("geometry", "coordinates")
      return false unless stop && last_stop && inbound.length >= 2 && outbound.length >= 2
      return false if meters(inbound.last, outbound.first) > JOIN_METERS

      cut = tail_projection(inbound, stop)
      return false unless cut

      index, point, overshoot = cut
      return false unless overshoot.between?(MIN_OVERSHOOT_METERS, MAX_OVERSHOOT_METERS)
      return false if passes?(head(outbound, RETURN_HEAD_METERS), stop)

      tail = [ point ] + inbound[(index + 1)..]
      return false if meters(last_stop, stop) > STOP_OFFSET_METERS && passes?(tail, last_stop)

      arriving["geometry"]["coordinates"] = inbound[0..index] + [ point ]
      departing["geometry"]["coordinates"] = straighten_join(tail + outbound.drop(1), tail.length - 1)
      true
    end

    # The old join vertex (often a few metres off the kerb, with a rounded
    # turnaround in front of it) is now mid-line; drop it when the line runs
    # straight past it rather than through a real turn.
    def straighten_join(line, join)
      return line if join <= 0 || join >= line.length - 1

      first = join
      first -= 1 while first > 1 && meters(line[first - 1], line[join]) <= JOIN_CLUSTER_METERS
      before = line[first - 1]
      after = line[join + 1]
      return line if meters(project(before, after, line[join]).first, line[join]) > MAX_JOIN_KINK_METERS

      line[0...first] + line[(join + 1)..]
    end

    # [segment index, projected point, metres from it to the line end] for the
    # stop's closest projection on the last MAX_OVERSHOOT_METERS-ish of line.
    def tail_projection(line, stop)
      best = nil
      remaining = 0.0
      (line.length - 2).downto(0) do |index|
        a = line[index]
        b = line[index + 1]
        point, t = project(a, b, stop)
        offset = meters(point, stop)
        along = remaining + (meters(a, b) * (1 - t))
        best = [ index, point, along, offset ] if offset <= STOP_OFFSET_METERS && (best.nil? || offset < best[3])
        remaining += meters(a, b)
        break if remaining > MAX_OVERSHOOT_METERS * 2
      end
      best&.first(3)
    end

    def passes?(line, stop)
      line.each_cons(2).any? { |a, b| meters(project(a, b, stop).first, stop) <= STOP_OFFSET_METERS }
    end

    def head(line, limit)
      total = 0.0
      line.each_with_index.take_while do |point, index|
        total += meters(line[index - 1], point) if index.positive?
        total <= limit || index < 2
      end.map(&:first)
    end

    def project(a, b, p)
      kx = 111_320.0 * Math.cos(a[1] * Math::PI / 180)
      bx = (b[0] - a[0]) * kx
      by = (b[1] - a[1]) * 110_540.0
      px = (p[0] - a[0]) * kx
      py = (p[1] - a[1]) * 110_540.0
      length2 = (bx * bx) + (by * by)
      t = length2.zero? ? 0.0 : (((px * bx) + (py * by)) / length2).clamp(0.0, 1.0)
      [ [ (a[0] + ((b[0] - a[0]) * t)).round(7), (a[1] + ((b[1] - a[1]) * t)).round(7) ], t ]
    end

    def meters(a, b)
      kx = 111_320.0 * Math.cos(a[1] * Math::PI / 180)
      Math.hypot((a[0] - b[0]) * kx, (a[1] - b[1]) * 110_540.0)
    end
  end
end
