# frozen_string_literal: true

module Geojson
  # Termini and interchange stations are where TDX shapes (and the joins between
  # a route's two directions) most often cut straight across blocks, car parks
  # and station forecourts, or double back on themselves. Near those places,
  # drop short back-and-forth hooks and re-drive off-road stretches along the
  # OSM street network.
  module BusRoadSnapper
    END_ZONE_METERS = 500.0
    HUB_ZONE_METERS = 250.0
    HUB_PATTERN = /轉運|總站|公車站|客運站|調度站|車站/
    MIN_SEGMENT_METERS = 20.0
    SAMPLE_STEP_METERS = 10.0
    SAMPLE_END_SKIP_METERS = 5.0
    OFF_ROAD_METERS = 15.0
    MIN_OFF_ROAD_PEAK_METERS = 20.0
    MIN_OFF_ROAD_FRACTION = 0.4
    MAX_DETOUR_RATIO = 2.5
    MAX_DETOUR_EXTRA_METERS = 300.0
    HOOK_ZONE_METERS = 80.0
    HOOK_TURN_DEGREES = 150.0
    HOOK_LEG_METERS = 40.0
    # Termini whose two directions stop short of each other (e.g. the last stop
    # is a block away from the first) are joined along the streets.
    MIN_JOIN_GAP_METERS = 15.0
    MAX_JOIN_GAP_METERS = 600.0
    U_TURN_LEG_METERS = 20.0
    U_TURN_DEGREES = 135.0
    # One-direction circulators whose TDX shape starts a block past the
    # terminus they finish at; the run out from the terminus is prepended.
    CLOSED_LOOP_ROUTE_IDS = %w[
      new_taipei_177_47105ddaf0
    ].freeze

    module_function

    def process_collection!(data, router: default_router)
      return false unless data.is_a?(Hash) && router

      features = Array(data["features"])
      hubs = features.filter_map do |feature|
        next unless feature.dig("properties", "feature_type") == "station"
        next unless feature.dig("properties", "name").to_s.match?(HUB_PATTERN)

        feature.dig("geometry", "coordinates")
      end
      changed = false
      features.each do |feature|
        next unless feature.dig("properties", "feature_type") == "route"
        next unless feature.dig("geometry", "type") == "LineString"

        line = feature.dig("geometry", "coordinates")
        snapped = snap_line(line, hubs, router)
        next if snapped == line

        feature["geometry"]["coordinates"] = snapped
        changed = true
      end
      changed = close_loop!(data.dig("properties", "id"), features, router) || changed
      join_termini!(features, router) || changed
    end

    def close_loop!(route_id, features, router)
      return false unless CLOSED_LOOP_ROUTE_IDS.include?(route_id)

      routes = features.select do |feature|
        feature.dig("properties", "feature_type") == "route" && feature.dig("geometry", "type") == "LineString"
      end
      return false unless routes.length == 1

      line = routes.first.dig("geometry", "coordinates")
      gap = meters_between(line.last, line.first)
      return false if line.length < 2 || gap < MIN_JOIN_GAP_METERS || gap > MAX_JOIN_GAP_METERS

      path = router.route(line.last, line.first)
      return false unless path

      routes.first["geometry"]["coordinates"] = ([ line.last ] + path + line).chunk_while { |a, b| a == b }.map(&:first)
      true
    end

    def join_termini!(features, router)
      routes = features.select do |feature|
        feature.dig("properties", "feature_type") == "route" && feature.dig("geometry", "type") == "LineString"
      end
      return false unless routes.length == 2

      lines = routes.map { |feature| feature.dig("geometry", "coordinates") }
      return false if lines.any? { |line| line.length < 2 || Geojson::BusLoopCloser.nearly_closed?(line) }

      changed = false
      [ [ 0, 1 ], [ 1, 0 ] ].each do |arriving, departing|
        from = lines[arriving].last
        to = lines[departing].first
        gap = meters_between(from, to)
        next if gap < MIN_JOIN_GAP_METERS || gap > MAX_JOIN_GAP_METERS

        path = router.route(from, to)
        next unless path && acceptable_detour?(from, to, path)

        lines[arriving] = (lines[arriving] + path + [ to ]).chunk_while { |a, b| a == b }.map(&:first)
        changed = true
      end
      routes.zip(lines).each { |feature, line| feature["geometry"]["coordinates"] = line } if changed
      changed
    end

    def default_router
      return nil unless Geojson::OsmRoadTiles.available?

      @default_router ||= Geojson::OsmRoadRouter.new
    end

    def snap_line(line, hubs, router)
      return line if line.length < 2

      line = drop_end_hooks(line)
      zone = zone_flags(line, hubs)
      bad = (0...(line.length - 1)).map { |index| zone[index] && off_road?(line[index], line[index + 1], router) }

      runs = []
      index = 0
      while index < bad.length
        unless bad[index]
          index += 1
          next
        end

        last = index
        last += 1 while last + 1 < bad.length && bad[last + 1]
        runs << [ index, last + 1 ]
        index = last + 1
      end

      runs.reverse_each do |first, last|
        path = router.route(line[first], line[last])
        next unless path && acceptable_detour?(line[first], line[last], path)

        line = line[0..first] + path + line[last..]
      end
      line.chunk_while { |a, b| a == b }.map(&:first)
    end

    # Segment i is in a zone when either of its ends is within END_ZONE_METERS
    # (along the line) of a line end, or within HUB_ZONE_METERS of a hub stop.
    def zone_flags(line, hubs)
      along = [ 0.0 ]
      line.each_cons(2) { |a, b| along << (along.last + meters_between(a, b)) }
      total = along.last
      near = line.each_with_index.map do |point, index|
        along[index] <= END_ZONE_METERS || total - along[index] <= END_ZONE_METERS ||
          hubs.any? { |hub| meters_between(point, hub) <= HUB_ZONE_METERS }
      end
      (0...(line.length - 1)).map { |index| near[index] || near[index + 1] }
    end

    def off_road?(a, b, router)
      length = meters_between(a, b)
      return false if length < MIN_SEGMENT_METERS

      steps = ((length - (2 * SAMPLE_END_SKIP_METERS)) / SAMPLE_STEP_METERS).floor
      return false if steps < 1

      distances = (0..steps).map do |step|
        t = (SAMPLE_END_SKIP_METERS + (step * SAMPLE_STEP_METERS)) / length
        router.distance_to_road([ a[0] + ((b[0] - a[0]) * t), a[1] + ((b[1] - a[1]) * t) ])
      end
      off = distances.count { |distance| distance > OFF_ROAD_METERS }
      off >= 2 && off >= distances.length * MIN_OFF_ROAD_FRACTION && distances.max >= MIN_OFF_ROAD_PEAK_METERS
    end

    def acceptable_detour?(from, to, path)
      straight = meters_between(from, to)
      length = path_length([ from ] + path + [ to ])
      return false if length > [ straight * MAX_DETOUR_RATIO, straight + MAX_DETOUR_EXTRA_METERS ].max

      !u_turn?([ from ] + path + [ to ])
    end

    # A path that doubles back (up one carriageway and down the other) reads as
    # a hairpin; better to leave the original geometry than draw one.
    def u_turn?(line)
      (1...(line.length - 1)).any? do |index|
        back = index - 1
        back -= 1 while back.positive? && meters_between(line[back], line[index]) < U_TURN_LEG_METERS
        ahead = index + 1
        ahead += 1 while ahead < line.length - 1 && meters_between(line[index], line[ahead]) < U_TURN_LEG_METERS
        next false if meters_between(line[back], line[index]) < U_TURN_LEG_METERS
        next false if meters_between(line[index], line[ahead]) < U_TURN_LEG_METERS

        turn_degrees(bearing(line[back], line[index]), bearing(line[index], line[ahead])) > U_TURN_DEGREES
      end
    end

    # Out-and-back flicks (a vertex the line turns sharply back from on a short
    # leg) within HOOK_ZONE_METERS of either end.
    def drop_end_hooks(line)
      loop do
        index = hook_index(line)
        return line unless index

        line = line[0...index] + line[(index + 1)..]
      end
    end

    def hook_index(line)
      return nil if line.length < 3

      along = [ 0.0 ]
      line.each_cons(2) { |a, b| along << (along.last + meters_between(a, b)) }
      total = along.last
      (1...(line.length - 1)).find do |index|
        next false unless along[index] <= HOOK_ZONE_METERS || total - along[index] <= HOOK_ZONE_METERS

        a, b, c = line[index - 1], line[index], line[index + 1]
        legs = [ meters_between(a, b), meters_between(b, c) ]
        next false if legs.min < 1.0 || legs.min > HOOK_LEG_METERS

        turn_degrees(bearing(a, b), bearing(b, c)) > HOOK_TURN_DEGREES
      end
    end

    def path_length(line)
      line.each_cons(2).sum { |a, b| meters_between(a, b) }
    end

    def bearing(from, to)
      dlon = (to[0] - from[0]) * Math.cos(from[1] * Math::PI / 180.0)
      Math.atan2(dlon, to[1] - from[1]) * 180.0 / Math::PI
    end

    def turn_degrees(from, to)
      ((to - from + 180.0) % 360.0 - 180.0).abs
    end

    def meters_between(left, right)
      Geojson::BusLoopCloser.meters_between(left, right)
    end
  end
end
