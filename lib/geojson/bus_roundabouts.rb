# frozen_string_literal: true

module Geojson
  # Routes through a roundabout follow its ring (counter-clockwise, right-hand
  # traffic) instead of the squared-off corner TDX shapes / sharpening leave.
  # Rings come from OpenStreetMap junction=roundabout ways (cache/roundabouts.json).
  module BusRoundabouts
    DATA_PATH = File.expand_path("cache/roundabouts.json", __dir__)
    APPROACH_METERS = 15.0
    APPROACH_FRACTION = 0.5
    ENTER_SLACK_METERS = 5.0
    DENSIFY_METERS = 4.0
    MIN_SWEEP_DEG = 30.0

    # Sides of a ring where TDX shapes hairpin out a side street and straight
    # back onto the ring; buses stay on the ring there. Bearings are degrees
    # counter-clockwise from east (see angle_of).
    SPUR_FREE_SIDES = [
      { center: [ 121.5634124, 25.0589013 ], from: -150.0, to: -30.0 } # 民生東路五段圓環, south
    ].freeze
    SPUR_MAX_METERS = 50.0
    SPUR_MAX_SWEEP_DEG = 90.0
    ON_RING_METERS = 3.0

    module_function

    def roundabouts
      @roundabouts ||= JSON.parse(File.read(DATA_PATH)).fetch("roundabouts").map do |row|
        center = row["center"]
        radius = row["radius"].to_f
        reach = row["reach"]&.to_f || (radius + [ APPROACH_METERS, radius * APPROACH_FRACTION ].max)
        { center:, radius:, reach:, ring: row["ring"], bbox: bbox_around(center, reach) }
      end
    end

    def process_collection!(data)
      return false unless data.is_a?(Hash)

      changed = false
      Array(data["features"]).each do |feature|
        next unless feature.dig("properties", "feature_type") == "route"
        next unless feature.dig("geometry", "type") == "LineString"

        line = feature.dig("geometry", "coordinates")
        routed = route_line(line)
        next if routed == line

        feature["geometry"]["coordinates"] = routed
        changed = true
      end
      changed
    end

    def route_line(line)
      return line if line.length < 2

      min_lon, max_lon = line.map(&:first).minmax
      min_lat, max_lat = line.map(&:last).minmax
      roundabouts.reduce(line) do |current, roundabout|
        b = roundabout[:bbox]
        next current if b[0] > max_lon || b[2] < min_lon || b[1] > max_lat || b[3] < min_lat

        through(without_spurs(current, roundabout), roundabout)
      end
    end

    def without_spurs(line, roundabout)
      center = roundabout[:center]
      sides = SPUR_FREE_SIDES.select { |side| meters_between(side[:center], center) < 1.0 }
      return line if sides.empty?

      on_ring = line.map { |point| near_ring?(roundabout, point) }
      result = []
      index = 0
      changed = false
      while index < line.length
        result << line[index]
        back = spur_end(line, on_ring, index, roundabout, sides)
        if back
          from_angle = angle_of(line[index], center)
          result.concat(ring_between(roundabout, from_angle, (angle_of(line[back], center) - from_angle) % 360.0))
          index = back
          changed = true
        else
          index += 1
        end
      end
      changed ? result : line
    end

    # Index where a hairpin leaving the ring at `index` rejoins it, if it does
    # so on a spur-free side, close by, and still heading counter-clockwise.
    def spur_end(line, on_ring, index, roundabout, sides)
      return unless on_ring[index] && index + 1 < line.length && !on_ring[index + 1]

      center = roundabout[:center]
      limit = roundabout[:radius] + SPUR_MAX_METERS
      back = (index + 1...line.length).find { |j| on_ring[j] || meters_between(line[j], center) > limit }
      return unless back && on_ring[back]

      from_angle = angle_of(line[index], center)
      to_angle = angle_of(line[back], center)
      return unless (to_angle - from_angle) % 360.0 < SPUR_MAX_SWEEP_DEG
      return unless sides.any? { |side| [ from_angle, to_angle ].all? { |angle| angle.between?(side[:from], side[:to]) } }

      back
    end

    def through(line, roundabout)
      center = roundabout[:center]
      dense = densify_near(line, center, roundabout[:reach])
      inside = dense.map { |point| meters_between(point, center) < roundabout[:reach] }
      ring_points = roundabout[:ring].to_h { |point| [ point, true ] }
      vertices = line.to_h { |point| [ point, true ] }

      result = []
      index = 0
      changed = false
      while index < dense.length
        unless inside[index]
          result << dense[index]
          index += 1
          next
        end

        last = index
        last += 1 while last + 1 < dense.length && inside[last + 1]
        run = dense[index..last]
        entered = run.any? { |point| meters_between(point, center) <= roundabout[:radius] + ENTER_SLACK_METERS }
        routed = run.any? { |point| ring_points[point] } ||
          run.count { |point| vertices[point] && on_ring?(roundabout, point) } >= 2
        if index.zero? || last + 1 >= dense.length || !entered || routed
          result.concat(run)
        else
          result.concat(ring_arc(roundabout, angle_of(run.first, center), angle_of(run.last, center)))
          changed = true
        end
        index = last + 1
      end
      changed ? result : line
    end

    # Ring from the entry bearing counter-clockwise to the exit bearing.
    def ring_arc(roundabout, from_angle, to_angle)
      sweep = (to_angle - from_angle) % 360.0
      sweep = 360.0 - MIN_SWEEP_DEG / 3 if sweep < MIN_SWEEP_DEG

      [ ring_point_at(roundabout, from_angle) ] + ring_between(roundabout, from_angle, sweep) + [ ring_point_at(roundabout, to_angle) ]
    end

    def ring_between(roundabout, from_angle, sweep)
      center = roundabout[:center]
      roundabout[:ring].filter_map { |point|
        offset = (angle_of(point, center) - from_angle) % 360.0
        [ offset, point ] if offset.positive? && offset < sweep
      }.sort_by(&:first).map { |_, point| point.dup }
    end

    def near_ring?(roundabout, point)
      center = roundabout[:center]
      (meters_between(point, center) - ring_radius_at(roundabout, angle_of(point, center))).abs < ON_RING_METERS
    end

    def ring_point_at(roundabout, angle)
      center = roundabout[:center]
      radius = ring_radius_at(roundabout, angle)
      radians = angle * Math::PI / 180.0
      kx = 111_320 * Math.cos(center[1] * Math::PI / 180.0)
      [ center[0] + (radius * Math.cos(radians) / kx), center[1] + (radius * Math.sin(radians) / 110_540) ]
    end

    def on_ring?(roundabout, point)
      center = roundabout[:center]
      (meters_between(point, center) - ring_radius_at(roundabout, angle_of(point, center))).abs < 0.05
    end

    def ring_radius_at(roundabout, angle)
      center = roundabout[:center]
      samples = roundabout[:ring].map { |point| [ angle_of(point, center), meters_between(point, center) ] }
      before = samples.min_by { |a, _| (angle - a) % 360.0 }
      after = samples.min_by { |a, _| (a - angle) % 360.0 }
      span = (after[0] - before[0]) % 360.0
      return before[1] if span.zero?

      t = ((angle - before[0]) % 360.0) / span
      before[1] + ((after[1] - before[1]) * t)
    end

    def densify_near(line, center, reach)
      result = [ line.first ]
      line.each_cons(2) do |a, b|
        if Geojson::BusShapeTrimmer.project(center, a, b)[:distance] < reach
          steps = (meters_between(a, b) / DENSIFY_METERS).ceil
          (1...steps).each do |step|
            t = step.to_f / steps
            result << [ a[0] + ((b[0] - a[0]) * t), a[1] + ((b[1] - a[1]) * t) ]
          end
        end
        result << b
      end
      result
    end

    # Counter-clockwise from east, in degrees.
    def angle_of(point, center)
      kx = 111_320 * Math.cos(center[1] * Math::PI / 180.0)
      Math.atan2((point[1] - center[1]) * 110_540, (point[0] - center[0]) * kx) * 180.0 / Math::PI
    end

    def bbox_around(center, meters)
      dlon = meters / (111_320 * Math.cos(center[1] * Math::PI / 180.0))
      dlat = meters / 110_540
      [ center[0] - dlon, center[1] - dlat, center[0] + dlon, center[1] + dlat ]
    end

    def meters_between(left, right)
      Geojson::BusLoopCloser.meters_between(left, right)
    end
  end
end
