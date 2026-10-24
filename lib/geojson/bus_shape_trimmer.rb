# frozen_string_literal: true

module Geojson
  # TDX sometimes ships a full out-and-back round trip as the Shape of a single
  # direction. Trim each direction's line to the span between its first and last
  # stop so direction banding does not draw the same street twice per direction.
  module BusShapeTrimmer
    MAX_ENDPOINT_GAP_METERS = 250.0
    MAX_STOP_GAP_METERS = 200.0
    MIN_REMOVED_METERS = 500.0
    MIN_REMOVED_FRACTION = 0.2
    MIN_MATCHED_PREFIX_FRACTION = 0.75
    MAX_PARTIAL_STRETCH = 1.6
    RESTORE_SNAP_METERS = 30.0
    MAX_RESTORED_METERS = 1_000.0
    SAME_TERMINUS_METERS = 150.0
    JOIN_GAP_METERS = 150.0
    MAX_JOIN_TURN_DEGREES = 120.0
    HEADING_SAMPLE_METERS = 30.0

    module_function

    # end_point: the opposite direction's first stop. When the shape reaches it
    # after the last stop, keep the terminus turnaround so both directions join.
    def trim_to_stops(coordinates, stop_points, end_point: nil, allow_partial: true)
      line = Array(coordinates).map { |point| [ point[0].to_f, point[1].to_f ] }
      stops = Array(stop_points).map { |point| [ point[0].to_f, point[1].to_f ] }
      return line if line.length < 2 || stops.length < 2
      return line if meters_between(stops.first, stops.last) <= SAME_TERMINUS_METERS

      matches = nil
      if end_point.present?
        extended = match_stops(line, stops + [ [ end_point[0].to_f, end_point[1].to_f ] ])
        matches = extended if stops_on_line?(extended, stops.length) &&
          extended.last[:distance] <= MAX_ENDPOINT_GAP_METERS
      end
      matches ||= match_stops(line, stops)
      unless stops_on_line?(matches, stops.length)
        # A trailing run of stops the Shape never visits (e.g. a terminal loop
        # TDX left out) should not block trimming the part that does match.
        return line unless allow_partial && end_point.present? && Geojson::BusLoopCloser.nearly_closed?(line)

        prefix = matches.index { |match| match[:distance] > MAX_STOP_GAP_METERS }
        return line if prefix < [ 2, (stops.length * MIN_MATCHED_PREFIX_FRACTION).ceil ].max

        partial = trim_to_stops(line, stops.first(prefix), end_point:, allow_partial: false)
        ratio = path_length(partial) / [ path_length(stops.first(prefix)), 1.0 ].max
        return ratio.between?(0.8, MAX_PARTIAL_STRETCH) ? partial : line
      end

      first, last = matches.first, matches.last
      return line if first[:distance] > MAX_ENDPOINT_GAP_METERS || last[:distance] > MAX_ENDPOINT_GAP_METERS

      trimmed = [ first[:point] ]
      ((first[:segment] + 1)..last[:segment]).each { |index| trimmed << line[index] }
      trimmed << last[:point]
      trimmed = trimmed.chunk_while { |a, b| a == b }.map(&:first)
      return line if trimmed.length < 2

      total = path_length(line)
      removed = total - path_length(trimmed)
      return line if removed < MIN_REMOVED_METERS || removed < total * MIN_REMOVED_FRACTION

      trimmed
    end

    def process_collection!(data)
      return false unless data.is_a?(Hash)

      features = Array(data["features"])
      stations = features.select { |feature| feature.dig("properties", "feature_type") == "station" }
      changed = false

      stops_by_direction = stations.group_by { |station| station.dig("properties", "direction").to_s }
        .transform_values { |rows| rows.map { |station| station.dig("geometry", "coordinates") } }

      originals = {}.compare_by_identity
      features.each do |feature|
        next unless feature.dig("properties", "feature_type") == "route"
        next unless feature.dig("geometry", "type") == "LineString"

        direction = feature.dig("properties", "direction").to_s
        originals[feature] = feature.dig("geometry", "coordinates")
        stop_points = stops_by_direction.fetch(direction, [])
        opposite = stops_by_direction.except(direction).values.first

        original = feature.dig("geometry", "coordinates")
        trimmed = trim_to_stops(original, stop_points, end_point: opposite&.first)
        next if trimmed.length == original.length && trimmed == original

        feature["geometry"]["coordinates"] = trimmed
        changed = true
      end

      routes = features.select { |feature|
        feature.dig("properties", "feature_type") == "route" && feature.dig("geometry", "type") == "LineString"
      }
      if routes.length == 2
        current = routes.map { |feature| feature.dig("geometry", "coordinates") }
        before = routes.map { |feature| originals[feature] || feature.dig("geometry", "coordinates") }
        lines = changed ? restore_handoffs(current, before) : current
        joined = join_termini(*lines)
        # Trimming that pulls the two directions apart is worse than leaving
        # the round trip alone.
        joined = before if handoff_gaps(joined).zip(handoff_gaps(before)).any? { |gap, old| gap > [ old, 0.0 ].max + JOIN_GAP_METERS }
        if joined != current
          routes.zip(joined).each { |feature, coords| feature["geometry"]["coordinates"] = coords }
          changed = true
        end
        changed = false if joined == before
      end

      return false unless changed

      routes.each do |feature|
        next if Geojson::BusLoopCloser.nearly_closed?(feature.dig("geometry", "coordinates"))

        feature["properties"].delete("loop")
      end
      data["properties"] ||= {}
      if routes.any? { |feature| feature.dig("properties", "loop") }
        data["properties"]["loop"] = true
      else
        data["properties"].delete("loop")
      end
      true
    end

    # Trimming can cut away the stretch that linked one direction's end to the
    # other's start (e.g. the drive from the last stop to the layover). When the
    # trimmed ends are too far apart to join, put that stretch back from
    # whichever original shape drove it.
    def restore_handoffs(lines, originals)
      outbound, inbound = lines
      outbound, inbound = restore_handoff(outbound, inbound, originals[0], originals[1])
      inbound, outbound = restore_handoff(inbound, outbound, originals[1], originals[0])
      [ outbound, inbound ]
    end

    def handoff_gaps(lines)
      outbound, inbound = lines
      [ meters_between(outbound.last, inbound.first), meters_between(inbound.last, outbound.first) ]
    end

    def restore_handoff(arriving, departing, arriving_original, departing_original)
      return [ arriving, departing ] if meters_between(arriving.last, departing.first) <= JOIN_GAP_METERS

      head = connecting_stretch(departing_original, arriving.last, departing.first)
      return [ arriving, head + departing.drop(1) ] if head

      tail = connecting_stretch(arriving_original, arriving.last, departing.first)
      return [ arriving[0...-1] + tail, departing ] if tail

      [ arriving, departing ]
    end

    # The part of `line` running from near `from` to near `to`, if it is short.
    def connecting_stretch(line, from, to)
      near = ->(point) {
        (0...(line.length - 1)).select { |index| project(point, line[index], line[index + 1])[:distance] <= RESTORE_SNAP_METERS }
      }
      finish = near.call(to)
      near.call(from).each do |first|
        last = finish.find { |index| index > first }
        next unless last

        stretch = [ from ] + line[(first + 1)..last] + [ to ]
        return stretch if path_length(stretch) <= MAX_RESTORED_METERS
      end
      nil
    end

    # Extend each direction to where the other one starts when they nearly meet
    # at a terminus, so the two lines read as one continuous route.
    def join_termini(outbound, inbound)
      return [ outbound, inbound ] if Array(outbound).length < 2 || Array(inbound).length < 2
      return [ outbound, inbound ] if Geojson::BusLoopCloser.nearly_closed?(outbound) ||
        Geojson::BusLoopCloser.nearly_closed?(inbound)

      outbound, inbound = connect(outbound, inbound)
      inbound, outbound = connect(inbound, outbound)
      [ outbound, inbound ]
    end

    # Close the gap between one direction's end and the next direction's start.
    # At a dead-end terminus the next direction usually starts a little way back
    # along the same street; extending the arriving line back there draws a
    # hook, so start the departing line at the dead end instead.
    def connect(arriving, departing)
      gap = meters_between(arriving.last, departing.first)
      return [ arriving, departing ] if gap.zero? || gap > JOIN_GAP_METERS

      link = bearing(arriving.last, departing.first)
      if turn_degrees(end_heading(arriving), link) <= MAX_JOIN_TURN_DEGREES
        [ arriving + [ departing.first ], departing ]
      elsif turn_degrees(link, start_heading(departing)) <= MAX_JOIN_TURN_DEGREES
        [ arriving, [ arriving.last ] + departing ]
      else
        [ arriving, departing ]
      end
    end

    def end_heading(line)
      index = line.length - 2
      index -= 1 while index.positive? && meters_between(line[index], line.last) < HEADING_SAMPLE_METERS
      bearing(line[index], line.last)
    end

    def start_heading(line)
      index = 1
      index += 1 while index < line.length - 1 && meters_between(line.first, line[index]) < HEADING_SAMPLE_METERS
      bearing(line.first, line[index])
    end

    def bearing(from, to)
      dlon = (to[0] - from[0]) * Math.cos(from[1] * Math::PI / 180.0)
      Math.atan2(dlon, to[1] - from[1]) * 180.0 / Math::PI
    end

    def turn_degrees(from, to)
      ((to - from + 180.0) % 360.0 - 180.0).abs
    end

    def stops_on_line?(matches, stop_count)
      matches.first(stop_count).all? { |match| match[:distance] <= MAX_STOP_GAP_METERS }
    end

    # Monotonic assignment of stops to segments minimising total stop→line distance.
    def match_stops(line, stops)
      segment_count = line.length - 1
      previous = nil
      back = []

      stops.each do |stop|
        projections = (0...segment_count).map { |index| project(stop, line[index], line[index + 1]) }
        costs = Array.new(segment_count)
        pointers = Array.new(segment_count)
        best_cost = Float::INFINITY
        best_index = nil

        segment_count.times do |index|
          if previous
            if previous[index] < best_cost
              best_cost = previous[index]
              best_index = index
            end
            costs[index] = best_cost + projections[index][:distance]
            pointers[index] = best_index
          else
            costs[index] = projections[index][:distance]
          end
        end

        back << { projections:, pointers: }
        previous = costs
      end

      segment = previous.each_with_index.min_by(&:first).last
      matches = []
      (stops.length - 1).downto(0) do |stop_index|
        step = back[stop_index]
        matches.unshift(step[:projections][segment].merge(segment:))
        segment = step[:pointers][segment] if stop_index.positive?
      end
      matches
    end

    def project(point, a, b)
      lat0 = point[1] * Math::PI / 180.0
      kx = 111_320 * Math.cos(lat0)
      ky = 110_540
      ax = (a[0] - point[0]) * kx
      ay = (a[1] - point[1]) * ky
      bx = (b[0] - point[0]) * kx
      by = (b[1] - point[1]) * ky
      dx = bx - ax
      dy = by - ay
      length_sq = (dx * dx) + (dy * dy)
      t = length_sq.zero? ? 0.0 : (-((ax * dx) + (ay * dy)) / length_sq).clamp(0.0, 1.0)
      px = ax + (dx * t)
      py = ay + (dy * t)
      {
        distance: Math.hypot(px, py),
        point: [ point[0] + (px / kx), point[1] + (py / ky) ]
      }
    end

    def path_length(line)
      line.each_cons(2).sum { |a, b| meters_between(a, b) }
    end

    def meters_between(left, right)
      Geojson::BusLoopCloser.meters_between(left, right)
    end
  end
end
