# frozen_string_literal: true

module Geojson
  # Shared track projection helpers for stations and depot spurs.
  module TrackGeometry
    # Only pull a station onto the centerline when it is already this close (meters).
    STATION_ALIGN_THRESHOLD_M = 25
    # Draw a depot spur when the facility is farther than this from the route (meters).
    DEPOT_EXTENSION_THRESHOLD_M = 50
    # Only force the spur endpoint onto the facility marker when already this close.
    FACILITY_ENDPOINT_SNAP_M = 100
    # Reject depot links that walk a passenger corridor instead of a local yard spur.
    MAX_DEPOT_SPUR_LENGTH_M = 3_500
    # Reject spurs that still contain a long straight closing/bridge chord.
    MAX_DEPOT_SPUR_SEGMENT_M = 300
    # Prefer facility vertices near the catalog hint (avoids far yard-network outliers).
    FACILITY_LOCAL_RADIUS_M = 500
    SPUR_NETWORK_VERTEX_SNAP_M = 8
    COORD_EPSILON = 0.0000001

    module_function

    def nearest_on_line_strings(lon, lat, line_strings)
      best_lon = lon
      best_lat = lat
      best_distance = Float::INFINITY

      line_strings.each do |coordinates|
        coordinates.each_cons(2) do |start, finish|
          projected_lon, projected_lat, distance = project_on_segment(lon, lat, start, finish)
          next unless distance < best_distance

          best_distance = distance
          best_lon = projected_lon
          best_lat = projected_lat
        end
      end

      [ best_lon, best_lat, best_distance ]
    end

    def align_point_to_lines(lon, lat, line_strings, threshold_m: STATION_ALIGN_THRESHOLD_M)
      projected_lon, projected_lat, distance = nearest_on_line_strings(lon, lat, line_strings)

      if distance <= threshold_m
        [ projected_lon, projected_lat ]
      else
        [ lon, lat ]
      end
    end

    # Returns [[track_lon, track_lat], [target_lon, target_lat]] or nil when already on track.
    def spur_coordinates_for_point(lon, lat, line_strings, threshold_m: DEPOT_EXTENSION_THRESHOLD_M)
      track_lon, track_lat, distance = nearest_on_line_strings(lon, lat, line_strings)
      return nil if distance <= threshold_m

      [ [ track_lon, track_lat ], [ lon, lat ] ]
    end

    # Follow route / yard track geometry from the main line to the depot (no straight-line shortcuts).
    def depot_link_coordinates_for_point(
      lon, lat, line_strings,
      spur_line_strings: nil,
      threshold_m: DEPOT_EXTENSION_THRESHOLD_M,
      junction_reference_lon: nil,
      junction_reference_lat: nil
    )
      return nil if line_strings.empty?

      spur_lines = Array(spur_line_strings).select { |coords| coords.length >= 2 }
      if spur_lines.any?
        return depot_link_via_spur_lines(
          lon, lat, line_strings, spur_lines,
          threshold_m: threshold_m,
          junction_reference_lon: junction_reference_lon,
          junction_reference_lat: junction_reference_lat
        )
      end

      _, _, distance = nearest_on_line_strings(lon, lat, line_strings)
      return nil if distance <= 0.5

      track_path = path_along_line_strings_toward_point(lon, lat, line_strings)
      if track_path.nil? || track_path.empty?
        track_lon, track_lat, = nearest_on_line_strings(lon, lat, line_strings)
        track_path = [ [ track_lon, track_lat ] ]
      end

      tail_distance = planar_distance_meters(track_path.last[0], track_path.last[1], lon, lat)
      return nil if tail_distance > threshold_m * 4 && distance > threshold_m

      finalized = finalize_depot_path(track_path, lon, lat)
      return nil if finalized && depot_spur_too_long?(finalized)
      return nil if finalized && depot_spur_has_long_closing_chord?(finalized)

      finalized
    end

    def facility_point_on_spur_network(catalog_lon, catalog_lat, spur_line_strings, main_line_strings)
      vertices = spur_line_strings.flat_map { |line| line }
      return [ catalog_lon, catalog_lat ] if vertices.empty?

      on_network = vertices.find do |point|
        planar_distance_meters(point[0], point[1], catalog_lon, catalog_lat) <= 1.0
      end
      return on_network if on_network

      candidates = vertices.select do |point|
        planar_distance_meters(point[0], point[1], catalog_lon, catalog_lat) <= FACILITY_LOCAL_RADIUS_M
      end
      if candidates.empty?
        candidates = vertices.min_by(8) do |point|
          planar_distance_meters(point[0], point[1], catalog_lon, catalog_lat)
        end
        candidates = Array(candidates)
      end

      candidates.max_by do |point|
        main_distance = nearest_on_line_strings(point[0], point[1], main_line_strings)[2]
        proximity = -planar_distance_meters(point[0], point[1], catalog_lon, catalog_lat)
        [ main_distance, proximity ]
      end
    end

    MAIN_LINE_JUNCTION_SNAP_M = 15

    def depot_link_via_spur_lines(
      lon, lat, main_line_strings, spur_line_strings,
      threshold_m: DEPOT_EXTENSION_THRESHOLD_M,
      junction_reference_lon: nil,
      junction_reference_lat: nil
    )
      facility_lon, facility_lat = facility_point_on_spur_network(lon, lat, spur_line_strings, main_line_strings)
      junction = spur_junction_to_main_line(
        spur_line_strings,
        main_line_strings,
        reference_lon: facility_lon,
        reference_lat: facility_lat,
        junction_reference_lon: junction_reference_lon,
        junction_reference_lat: junction_reference_lat
      )
      return nil unless junction

      spur_path = spur_path_from_junction(junction, facility_lon, facility_lat, spur_line_strings)
      spur_path = prepend_junction_to_spur_path(junction, spur_path)
      spur_path = enrich_spur_path(facility_lon, facility_lat, spur_line_strings, spur_path)
      spur_path = prefer_local_facility_spur_path(
        spur_path, facility_lon, facility_lat, spur_line_strings, main_line_strings,
        junction_reference_lon: junction_reference_lon,
        junction_reference_lat: junction_reference_lat
      )
      return nil if spur_path.nil? || spur_path.empty?

      main_path = main_line_junction_path(spur_path.first[0], spur_path.first[1], main_line_strings)
      path = dedupe_coordinates(main_path + spur_path)
      finalized = finalize_depot_path(
        path,
        facility_lon,
        facility_lat,
        threshold_m: threshold_m,
        require_track_geometry: true
      )
      return nil if finalized && depot_spur_too_long?(finalized)
      return nil if finalized && depot_spur_corridor_duplicate?(finalized, main_line_strings)

      finalized
    end

    # When yard discovery returns disconnected clusters, prefer the cluster at the facility
    # over approach tracks that never reach the depot.
    def prefer_local_facility_spur_path(
      spur_path, facility_lon, facility_lat, spur_line_strings, main_line_strings,
      junction_reference_lon: nil,
      junction_reference_lat: nil
    )
      return spur_path if spur_path.nil? || spur_path.empty?

      tail_distance = planar_distance_meters(
        spur_path.last[0], spur_path.last[1], facility_lon, facility_lat
      )
      return spur_path if tail_distance <= FACILITY_ENDPOINT_SNAP_M * 2

      local_lines = spur_line_strings.select do |line|
        line.any? do |point|
          planar_distance_meters(point[0], point[1], facility_lon, facility_lat) <= FACILITY_LOCAL_RADIUS_M
        end
      end
      return spur_path if local_lines.empty?

      local_junction = spur_junction_to_main_line(
        local_lines,
        main_line_strings,
        reference_lon: facility_lon,
        reference_lat: facility_lat,
        junction_reference_lon: junction_reference_lon,
        junction_reference_lat: junction_reference_lat
      )
      return spur_path unless local_junction

      _, _, junction_gap = nearest_on_line_strings(
        local_junction[0], local_junction[1], main_line_strings
      )
      return spur_path if junction_gap > MAX_DEPOT_SPUR_SEGMENT_M

      local_path = spur_path_from_junction(local_junction, facility_lon, facility_lat, local_lines)
      local_path = prepend_junction_to_spur_path(local_junction, local_path)
      local_path = enrich_spur_path(facility_lon, facility_lat, local_lines, local_path)
      return spur_path if local_path.nil? || local_path.empty?

      local_tail = planar_distance_meters(local_path.last[0], local_path.last[1], facility_lon, facility_lat)
      local_tail < tail_distance ? local_path : spur_path
    end

    def spur_junction_to_main_line(
      spur_line_strings,
      main_line_strings,
      reference_lon:,
      reference_lat:,
      junction_reference_lon: nil,
      junction_reference_lat: nil
    )
      if junction_reference_lon && junction_reference_lat
        main_lon, main_lat, = nearest_on_line_strings(
          junction_reference_lon, junction_reference_lat, main_line_strings
        )
        return [ main_lon, main_lat ]
      end

      vertices = dedupe_coordinates(spur_line_strings.flat_map { |line| line })
      return nil if vertices.empty?

      snapped = vertices.select do |point|
        nearest_on_line_strings(point[0], point[1], main_line_strings)[2] <= MAIN_LINE_JUNCTION_SNAP_M
      end

      if snapped.any?
        snapped.min_by do |point|
          main_distance = nearest_on_line_strings(point[0], point[1], main_line_strings)[2]
          yard_distance = planar_distance_meters(point[0], point[1], reference_lon, reference_lat)
          [ main_distance, -yard_distance ]
        end
      else
        vertices.min_by do |point|
          nearest_on_line_strings(point[0], point[1], main_line_strings)[2]
        end
      end
    end

    def main_line_junction_path(junction_lon, junction_lat, main_line_strings)
      main_lon, main_lat, distance = nearest_on_line_strings(junction_lon, junction_lat, main_line_strings)
      return [] if distance <= 1.0

      [ [ main_lon, main_lat ] ]
    end

    def prepend_junction_to_spur_path(junction, spur_path)
      return spur_path if spur_path.nil? || spur_path.empty?

      junction_lon, junction_lat = junction
      first_lon, first_lat = spur_path.first
      return spur_path if planar_distance_meters(first_lon, first_lat, junction_lon, junction_lat) <= 5

      dedupe_coordinates([ junction ] + spur_path)
    end

    def spur_path_from_junction(junction, target_lon, target_lat, spur_line_strings)
      network_path = spur_path_via_line_network(junction, target_lon, target_lat, spur_line_strings)
      return network_path if network_path&.length.to_i >= 2

      best_path = nil
      best_tail_distance = Float::INFINITY

      spur_line_strings.each do |coordinates|
        path = path_along_line_string_from_vertex(coordinates, junction, target_lon, target_lat)
        next if path.nil? || path.empty?

        tail_distance = planar_distance_meters(path.last[0], path.last[1], target_lon, target_lat)
        next unless tail_distance < best_tail_distance

        best_tail_distance = tail_distance
        best_path = path
      end

      best_path
    end

    def spur_path_via_line_network(junction, target_lon, target_lat, spur_line_strings)
      graph, vertices = build_spur_line_graph(spur_line_strings)
      return nil if graph.empty?

      start = vertices.min_by do |vertex|
        planar_distance_meters(vertex[0], vertex[1], junction[0], junction[1])
      end
      return nil if planar_distance_meters(start[0], start[1], junction[0], junction[1]) > 100

      distances = { start => 0.0 }
      paths = { start => [ start ] }
      queue = [ start ]
      best_path = [ start ]
      best_tail = planar_distance_meters(start[0], start[1], target_lon, target_lat)
      visited = {}

      until queue.empty?
        node = queue.min_by { |vertex| distances[vertex] + planar_distance_meters(vertex[0], vertex[1], target_lon, target_lat) }
        queue.delete(node)
        next if visited[node]

        visited[node] = true
        tail = planar_distance_meters(node[0], node[1], target_lon, target_lat)
        if tail < best_tail
          best_tail = tail
          best_path = paths[node]
        end
        break if tail <= FACILITY_ENDPOINT_SNAP_M

        graph.fetch(node, {}).each do |neighbor, edge_distance|
          next if visited[neighbor]

          candidate = distances[node] + edge_distance
          next if distances[neighbor] && candidate >= distances[neighbor]

          distances[neighbor] = candidate
          paths[neighbor] = paths[node] + [ neighbor ]
          queue << neighbor unless queue.include?(neighbor)
        end
      end

      return nil if best_path.nil? || best_path.length < 2

      dedupe_coordinates(best_path)
    end

    def build_spur_line_graph(spur_line_strings)
      registry = []
      graph = Hash.new { |hash, key| hash[key] = {} }

      spur_line_strings.each do |coordinates|
        coordinates.each_cons(2) do |start, finish|
          from = snap_spur_vertex(start, registry)
          to = snap_spur_vertex(finish, registry)
          next if same_coordinate?(from, to)

          distance = planar_distance_meters(from[0], from[1], to[0], to[1])
          graph[from][to] = distance
          graph[to][from] = distance
        end
      end

      [ graph, registry ]
    end

    def snap_spur_vertex(point, registry)
      registry.each do |existing|
        return existing if planar_distance_meters(point[0], point[1], existing[0], existing[1]) <= SPUR_NETWORK_VERTEX_SNAP_M
      end

      registry << point
      point
    end

    def path_along_line_string_from_vertex(coordinates, junction, target_lon, target_lat)
      return [] if coordinates.length < 2

      index = coordinates.each_index.min_by do |vertex_index|
        planar_distance_meters(coordinates[vertex_index][0], coordinates[vertex_index][1], junction[0], junction[1])
      end
      return [] if planar_distance_meters(coordinates[index][0], coordinates[index][1], junction[0], junction[1]) > 100

      from_start = walk_from_index(coordinates, index, target_lon, target_lat, forward: true)
      from_end = walk_from_index(coordinates, index, target_lon, target_lat, forward: false)

      start_tail = planar_distance_meters(from_start.last[0], from_start.last[1], target_lon, target_lat)
      end_tail = planar_distance_meters(from_end.last[0], from_end.last[1], target_lon, target_lat)

      start_tail <= end_tail ? from_start : from_end
    end

    def walk_from_index(coordinates, index, target_lon, target_lat, forward:)
      path = [ coordinates[index] ]
      vertices = if forward
        coordinates[(index + 1)..]
      else
        coordinates[0...index].reverse
      end
      previous_distance = planar_distance_meters(path.last[0], path.last[1], target_lon, target_lat)

      vertices.each do |vertex|
        vertex_distance = planar_distance_meters(vertex[0], vertex[1], target_lon, target_lat)
        break if vertex_distance > previous_distance + 0.5

        path << vertex unless same_coordinate?(path.last, vertex)
        previous_distance = vertex_distance
      end

      dedupe_coordinates(path)
    end

    def enrich_spur_path(target_lon, target_lat, spur_line_strings, spur_path)
      return spur_path if spur_path.nil?
      return spur_path if spur_path.length >= 2

      longest = spur_line_strings.max_by(&:length)
      return spur_path unless longest

      from_start = walk_from_endpoint(longest, target_lon, target_lat, from_start: true)
      from_end = walk_from_endpoint(longest, target_lon, target_lat, from_start: false)

      start_tail = planar_distance_meters(from_start.last[0], from_start.last[1], target_lon, target_lat)
      end_tail = planar_distance_meters(from_end.last[0], from_end.last[1], target_lon, target_lat)

      better =
        if (start_tail - end_tail).abs <= 0.5
          from_start.length >= from_end.length ? from_start : from_end
        elsif start_tail <= end_tail
          from_start
        else
          from_end
        end
      better.length >= 2 ? better : spur_path
    end

    def path_along_line_strings_toward_point(target_lon, target_lat, line_strings)
      best_path = nil
      best_tail_distance = Float::INFINITY

      line_strings.each do |coordinates|
        path = path_along_line_string_toward_point(coordinates, target_lon, target_lat)
        next if path.nil? || path.empty?

        tail_distance = planar_distance_meters(path.last[0], path.last[1], target_lon, target_lat)
        next unless tail_distance < best_tail_distance

        best_tail_distance = tail_distance
        best_path = path
      end

      best_path
    end

    def path_along_line_string_toward_point(coordinates, target_lon, target_lat)
      return [] if coordinates.length < 2

      from_start = walk_from_endpoint(coordinates, target_lon, target_lat, from_start: true)
      from_end = walk_from_endpoint(coordinates, target_lon, target_lat, from_start: false)

      start_tail = planar_distance_meters(from_start.last[0], from_start.last[1], target_lon, target_lat)
      end_tail = planar_distance_meters(from_end.last[0], from_end.last[1], target_lon, target_lat)

      start_tail <= end_tail ? from_start : from_end
    end

    def walk_from_endpoint(coordinates, target_lon, target_lat, from_start:)
      path = [ from_start ? coordinates.first : coordinates.last ]
      vertices = from_start ? coordinates[1..] : coordinates[0...-1].reverse
      previous_distance = planar_distance_meters(path.last[0], path.last[1], target_lon, target_lat)

      vertices.each do |vertex|
        vertex_distance = planar_distance_meters(vertex[0], vertex[1], target_lon, target_lat)
        break if vertex_distance > previous_distance + 0.5

        path << vertex unless same_coordinate?(path.last, vertex)
        previous_distance = vertex_distance
      end

      dedupe_coordinates(path)
    end

    def path_from_projection(coordinates, segment_idx, projection, forward:, target_lon:, target_lat:)
      path = [ projection ]
      previous_distance = planar_distance_meters(projection[0], projection[1], target_lon, target_lat)

      vertices = if forward
        coordinates[(segment_idx + 1)..]
      else
        coordinates[0..segment_idx].reverse
      end

      vertices.each do |vertex|
        vertex_distance = planar_distance_meters(vertex[0], vertex[1], target_lon, target_lat)
        break if vertex_distance > previous_distance + 0.5

        path << vertex unless same_coordinate?(path.last, vertex)
        previous_distance = vertex_distance
      end

      dedupe_coordinates(path)
    end

    def finalize_depot_path(path, lon, lat, threshold_m: DEPOT_EXTENSION_THRESHOLD_M, require_track_geometry: false)
      return nil if path.nil? || path.empty?

      coordinates = dedupe_coordinates(path)
      tail_distance = planar_distance_meters(coordinates.last[0], coordinates.last[1], lon, lat)
      if tail_distance > 0.5 && tail_distance <= FACILITY_ENDPOINT_SNAP_M
        coordinates << [ lon, lat ]
        coordinates[-1] = [ lon, lat ]
      end

      return nil if coordinates.length < 2
      if require_track_geometry
        length = path_length_meters(coordinates)
        # Short yard connectors may be nearly straight; reject long straight shortcuts only.
        return nil if coordinates.length < 3 && length > 400
        return nil if straight_line?(coordinates) && length > 400
      end
      return nil if coordinates.length == 2 && straight_line?(coordinates) &&
        planar_distance_meters(coordinates.first[0], coordinates.first[1], lon, lat) > threshold_m

      coordinates
    end

    def depot_spur_too_long?(coordinates)
      return false if coordinates.length < 2

      path_length_meters(coordinates) > MAX_DEPOT_SPUR_LENGTH_M
    end

    def depot_spur_has_long_closing_chord?(coordinates, max_segment_m: MAX_DEPOT_SPUR_SEGMENT_M)
      return false if coordinates.length < 2

      start = coordinates[-2]
      finish = coordinates[-1]
      planar_distance_meters(start[0], start[1], finish[0], finish[1]) > max_segment_m
    end

    def depot_spur_corridor_duplicate?(coordinates, main_line_strings)
      length = path_length_meters(coordinates)
      overlap = main_line_overlap_ratio(coordinates, main_line_strings)
      return true if length > 2_000 && overlap > 0.35
      return true if length > 1_200 && overlap > 0.85
      # Short approach tracks that never leave the passenger corridor toward the yard.
      return true if length < 500 && overlap > 0.7

      false
    end

    def path_length_meters(coordinates)
      return 0.0 if coordinates.nil? || coordinates.length < 2

      coordinates.each_cons(2).sum do |start, finish|
        planar_distance_meters(start[0], start[1], finish[0], finish[1])
      end
    end

    # Average two parallel OSM direction tracks into a single corridor centerline.
    def average_parallel_line_strings(primary, secondary, sample_m: 50, max_pair_m: 80)
      return primary if primary.nil? || primary.length < 2
      return primary if secondary.nil? || secondary.length < 2

      oriented = orient_line_string_toward(secondary, primary.first)
      resample_polyline(primary, sample_m).map do |point|
        lon, lat, distance = nearest_on_line_strings(point[0], point[1], [ oriented ])
        if distance <= max_pair_m
          [ (point[0] + lon) / 2.0, (point[1] + lat) / 2.0 ]
        else
          point
        end
      end
    end

    def orient_line_string_toward(coordinates, target)
      start_distance = planar_distance_meters(coordinates.first[0], coordinates.first[1], target[0], target[1])
      end_distance = planar_distance_meters(coordinates.last[0], coordinates.last[1], target[0], target[1])
      start_distance <= end_distance ? coordinates : coordinates.reverse
    end

    # Drop a short beyond-terminal stub, then snap that end onto the station.
    def trim_terminal_stub_and_snap(coordinates, point, max_stub_m: 200, snap_m: 150)
      return coordinates if coordinates.nil? || coordinates.length < 2 || point.nil?

      best_index = 0
      best_distance = Float::INFINITY
      coordinates.each_with_index do |coord, index|
        distance = planar_distance_meters(coord[0], coord[1], point[0], point[1])
        next unless distance < best_distance

        best_distance = distance
        best_index = index
      end
      return coordinates if best_distance > snap_m

      from_start = path_length_meters(coordinates[0..best_index])
      from_end = path_length_meters(coordinates[best_index..])

      if best_index.positive? && from_start <= max_stub_m && from_start <= from_end
        return [ point ] + coordinates[(best_index + 1)..]
      end

      if best_index < coordinates.length - 1 && from_end <= max_stub_m && from_end < from_start
        return coordinates[0...best_index] + [ point ]
      end

      snapped = coordinates.dup
      start_distance = planar_distance_meters(snapped.first[0], snapped.first[1], point[0], point[1])
      end_distance = planar_distance_meters(snapped.last[0], snapped.last[1], point[0], point[1])
      if start_distance <= snap_m && start_distance <= end_distance
        snapped[0] = point
      elsif end_distance <= snap_m
        snapped[-1] = point
      end
      snapped
    end

    def resample_polyline(coordinates, sample_m)
      return coordinates if coordinates.length < 2 || sample_m.to_f <= 0

      sampled = [ coordinates.first ]
      carry = 0.0

      coordinates.each_cons(2) do |start, finish|
        segment = planar_distance_meters(start[0], start[1], finish[0], finish[1])
        next if segment <= 0

        direction_lon = (finish[0] - start[0]) / segment
        direction_lat = (finish[1] - start[1]) / segment
        cursor = sample_m - carry

        while cursor <= segment
          sampled << [
            start[0] + (direction_lon * cursor),
            start[1] + (direction_lat * cursor)
          ]
          cursor += sample_m
        end

        carry = segment - (cursor - sample_m)
      end

      unless same_coordinate?(sampled.last, coordinates.last)
        sampled << coordinates.last
      end

      sampled
    end

    def main_line_overlap_ratio(spur_coordinates, main_line_strings, tolerance_m: 8)
      return 0.0 if spur_coordinates.nil? || spur_coordinates.empty? || main_line_strings.empty?

      shared = spur_coordinates.count do |point|
        nearest_on_line_strings(point[0], point[1], main_line_strings)[2] <= tolerance_m
      end
      shared.to_f / spur_coordinates.length
    end

    def straight_line?(coordinates)
      return true if coordinates.length <= 2

      start = coordinates.first
      finish = coordinates.last
      coordinates.all? do |point|
        _, _, distance = project_on_segment(point[0], point[1], start, finish)
        distance < 1.0
      end
    end

    def dedupe_coordinates(coordinates)
      coordinates.each_with_object([]) do |coordinate, unique|
        unique << coordinate unless unique.last && same_coordinate?(unique.last, coordinate)
      end
    end

    def densify_coordinates(coordinates, max_step_m:)
      return coordinates if coordinates.length < 2

      step = max_step_m.to_f
      return coordinates if step <= 0.0

      densified = [ coordinates.first ]

      coordinates.each_cons(2) do |start, finish|
        gap = planar_distance_meters(start[0], start[1], finish[0], finish[1])
        if gap > step
          steps = (gap / step).ceil
          (1...steps).each do |index|
            ratio = index.to_f / steps
            densified << [
              start[0] + ((finish[0] - start[0]) * ratio),
              start[1] + ((finish[1] - start[1]) * ratio)
            ]
          end
        end

        densified << finish
      end

      densified
    end

    def same_coordinate?(left, right)
      (left[0] - right[0]).abs < COORD_EPSILON && (left[1] - right[1]).abs < COORD_EPSILON
    end

    def project_on_segment(lon, lat, start_coord, end_coord)
      start_lon, start_lat = start_coord
      end_lon, end_lat = end_coord
      delta_lon = end_lon - start_lon
      delta_lat = end_lat - start_lat

      t = if delta_lon.zero? && delta_lat.zero?
        0.0
      else
        raw = ((lon - start_lon) * delta_lon + (lat - start_lat) * delta_lat) /
              (delta_lon * delta_lon + delta_lat * delta_lat)
        [ [ raw, 0.0 ].max, 1.0 ].min
      end

      projected_lon = start_lon + (t * delta_lon)
      projected_lat = start_lat + (t * delta_lat)
      distance = planar_distance_meters(lon, lat, projected_lon, projected_lat)

      [ projected_lon, projected_lat, distance ]
    end

    def planar_distance_meters(lon_a, lat_a, lon_b, lat_b)
      lat_mid_rad = ((lat_a + lat_b) / 2.0) * Math::PI / 180.0
      delta_lat = (lat_b - lat_a) * 111_320.0
      delta_lon = (lon_b - lon_a) * 111_320.0 * Math.cos(lat_mid_rad)

      Math.sqrt((delta_lat * delta_lat) + (delta_lon * delta_lon))
    end

    def route_line_strings_from_geojson(path)
      data = JSON.parse(path.read)
      lines = []

      data.fetch("features", []).each do |feature|
        feature_type = feature.dig("properties", "feature_type")
        next unless %w[route express_route].include?(feature_type)

        geometry = feature["geometry"]
        case geometry["type"]
        when "LineString"
          lines << geometry["coordinates"]
        when "MultiLineString"
          lines.concat(geometry["coordinates"])
        end
      end

      lines
    end
  end
end
