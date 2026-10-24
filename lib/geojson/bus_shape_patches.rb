# frozen_string_literal: true

module Geojson
  # Hand-checked corrections for TDX Shape errors (overshoots, corner cuts).
  # Each patch replaces the stretch between two existing shape vertices with a
  # road-following path (OSM geometry); `from`/`to` must be vertices of the shape.
  module BusShapePatches
    PATCHES = {
      # Plain 223 goes straight from 中華路 down the connector onto 國興路 to
      # 青年公園(國興); the 青年社宅 loop round the park is the 繞駛 variant.
      "taipei_223" => [
        {
          direction: 0,
          from: [ 121.5066148, 25.0262803 ],
          to: [ 121.5065415, 25.0259529 ],
          path: [
            [ 121.5065491, 25.0261631 ],
            [ 121.5064865, 25.0260948 ],
            [ 121.5064931, 25.0260137 ],
            [ 121.5065148, 25.0259871 ]
          ]
        }
      ],
      "taipei_20" => [
        # 松山路 → left onto 信義路六段 at the intersection, not a hairpin 20 m past it.
        {
          direction: 0,
          from: [ 121.578619, 25.035868 ],
          to: [ 121.576809, 25.035321 ],
          path: [
            [ 121.578550, 25.035936 ],
            [ 121.578490, 25.036150 ],
            [ 121.578474, 25.036275 ],
            [ 121.578402, 25.036260 ],
            [ 121.577979, 25.036153 ],
            [ 121.577915, 25.036140 ],
            [ 121.577876, 25.036109 ],
            [ 121.576864, 25.035342 ]
          ]
        }
      ],
      "taipei_33_17461a8442" => [
        # After the 永春里 loop: 福德街 out to 捷運廣慈/奉天宮站(福德) and back
        # past 信義行政中心 to 松山商職(福德).
        {
          direction: 0,
          from: [ 121.578323, 25.036278 ],
          to: [ 121.577989, 25.036193 ],
          path: [
            [ 121.579374, 25.036393 ], [ 121.580299, 25.036720 ], [ 121.582670, 25.037621 ],
            [ 121.583358, 25.037876 ], [ 121.583894, 25.038110 ], [ 121.583362, 25.037869 ],
            [ 121.582668, 25.037616 ], [ 121.580292, 25.036708 ], [ 121.579370, 25.036383 ],
            [ 121.578811, 25.036348 ]
          ]
        },
        # Down 大道路, then 福德街 out to 松山商職(福德) and back east.
        {
          direction: 1,
          from: [ 121.583933, 25.038033 ],
          to: [ 121.584135, 25.038257 ],
          path: [
            [ 121.582887, 25.037628 ], [ 121.582132, 25.037341 ], [ 121.580561, 25.036743 ],
            [ 121.579602, 25.036345 ], [ 121.578817, 25.036264 ], [ 121.578399, 25.036203 ],
            [ 121.578817, 25.036261 ], [ 121.579604, 25.036339 ], [ 121.580567, 25.036733 ],
            [ 121.582140, 25.037338 ], [ 121.582889, 25.037619 ], [ 121.583631, 25.037900 ]
          ]
        }
      ]
    }.freeze
    VERTEX_MATCH_METERS = 3.0

    # Shapes that include a detour only some trips run: everything between the
    # first and last pass of `anchor` (the junction where the detour leaves
    # the plain route) is dropped.
    EXCURSIONS = {
      # 永春里／大道路 loop is the 繞駛 variant; plain 33 stays on 福德街.
      "taipei_33" => [
        { direction: 0, anchor: [ 121.583855, 25.038199 ] }, # 福德街／大道路
        { direction: 1, anchor: [ 121.578410, 25.036250 ] }  # 福德街／松山路
      ]
    }.freeze
    EXCURSION_ANCHOR_METERS = 30.0
    MIN_EXCURSION_METERS = 300.0

    # Off-street stops where every route runs the same internal circulation.
    # A route's visit (the part of its line inside `bounds`, passing the stop)
    # is replaced by the path for the side it enters from; `west_of` splits
    # the entry sides. Visits that do not return to the west side are left alone.
    TRI_SERVICE_LOOP = [
      # 西迴一樓: north-east along the south drive, round the platform, out north-west.
      [ 121.591995, 25.071488 ], [ 121.592098, 25.071542 ], [ 121.592151, 25.071600 ],
      [ 121.592175, 25.071628 ], [ 121.592208, 25.071690 ], [ 121.592226, 25.071757 ],
      [ 121.592228, 25.071827 ], [ 121.592214, 25.071895 ], [ 121.592185, 25.071959 ],
      [ 121.592160, 25.071992 ], [ 121.592128, 25.072022 ], [ 121.592017, 25.072119 ],
      [ 121.591600, 25.072366 ], [ 121.591549, 25.072396 ],
      # Back down to the exit drive and west to 成功路.
      [ 121.591237, 25.072178 ], [ 121.591041, 25.072041 ], [ 121.591016, 25.071951 ],
      [ 121.590901, 25.071965 ], [ 121.590261, 25.071981 ]
    ].freeze
    STOP_CIRCULATIONS = {
      "三總內湖站" => {
        bounds: [ 121.5900, 25.0706, 121.5927, 25.0728 ],
        west_of: 121.5900,
        max_stop_meters: 60.0,
        paths: {
          # From 成功路 along the entry drive.
          west: [
            [ 121.590254, 25.071701 ], [ 121.590893, 25.071686 ], [ 121.591009, 25.071693 ],
            [ 121.591036, 25.071584 ], [ 121.591202, 25.071458 ], [ 121.591516, 25.071221 ]
          ] + TRI_SERVICE_LOOP,
          # From the east along the south service road, then up the one-way alley.
          east: [
            [ 121.592196, 25.070866 ], [ 121.592127, 25.070870 ], [ 121.592082, 25.070872 ],
            [ 121.591977, 25.070903 ]
          ] + TRI_SERVICE_LOOP
        }
      }
    }.freeze
    # Terminals where the joined line cuts straight from the arrival stop to the
    # departure stop: a line ending at `departure` right after a vertex near
    # `arrival` gets that last hop redrawn along `path` (the terminal lane).
    TERMINAL_APPROACHES = [
      {
        # 萬芳社區: from 萬美街 south through the bus lot to the 萬安街 side.
        name: "萬芳社區",
        arrival: [ 121.569816, 25.002253 ],
        departure: [ 121.570457, 25.001753 ],
        arrival_meters: 30.0,
        departure_meters: 15.0,
        path: [
          [ 121.569899, 25.002318 ], [ 121.569898, 25.002252 ], [ 121.569897, 25.001831 ], [ 121.570450, 25.001830 ]
        ]
      }
    ].freeze
    # Off-street terminal loops: a line ending (starting) at `stop` has its
    # stretch from the first (to the last) vertex within `join_meters` of the
    # street junction replaced by the `arrival` (`departure`) half of the loop.
    TERMINAL_LOOPS = [
      {
        # 陽明山國家公園管理處 (第二停車場): one-way off 竹子湖路 south-west to
        # the lot, round past the terminus, back north-east to 竹子湖路.
        name: "陽明山國家公園管理處",
        stop: [ 121.544693, 25.153887 ],
        stop_meters: 30.0,
        join_meters: 30.0,
        arrival: [
          [ 121.545928, 25.155456 ], [ 121.545800, 25.155369 ], [ 121.545747, 25.155312 ], [ 121.545679, 25.155243 ],
          [ 121.545625, 25.155189 ], [ 121.545593, 25.155158 ], [ 121.545473, 25.155046 ], [ 121.545433, 25.155004 ],
          [ 121.545336, 25.154908 ], [ 121.545084, 25.154644 ], [ 121.544960, 25.154576 ], [ 121.544793, 25.154397 ],
          [ 121.544699, 25.154309 ], [ 121.544591, 25.154181 ], [ 121.544560, 25.154118 ], [ 121.544594, 25.154074 ],
          [ 121.544753, 25.153999 ]
        ],
        departure: [
          [ 121.544753, 25.153999 ], [ 121.545071, 25.153850 ], [ 121.545200, 25.153829 ], [ 121.545353, 25.153909 ],
          [ 121.545413, 25.153979 ], [ 121.545461, 25.154082 ], [ 121.545605, 25.154409 ], [ 121.545743, 25.154735 ],
          [ 121.545870, 25.155029 ], [ 121.545887, 25.155065 ], [ 121.545905, 25.155098 ], [ 121.545956, 25.155146 ],
          [ 121.546007, 25.155183 ], [ 121.546108, 25.155257 ]
        ]
      },
      {
        # 天母: up 中山北路七段 (northbound side) past the drop-off, once round
        # 天母圓環 counter-clockwise, back down the southbound side to the
        # boarding stop. TDX ends both directions at one point by the east kerb;
        # the small stop_meters keeps a re-run from matching the patched ends.
        name: "天母",
        stop: [ 121.532700785386, 25.1243016019796 ],
        stop_meters: 8.0,
        join_meters: 30.0,
        arrival: [
          [ 121.532713, 25.1244508 ], [ 121.5327569, 25.1245677 ], [ 121.5327992, 25.1245685 ], [ 121.53284, 25.1245784 ],
          [ 121.532877, 25.1245969 ], [ 121.5329081, 25.1246229 ], [ 121.5329314, 25.1246549 ], [ 121.5329455, 25.124691 ],
          [ 121.5329497, 25.124729 ], [ 121.5329438, 25.1247669 ], [ 121.5329279, 25.1248024 ], [ 121.5329032, 25.1248335 ],
          [ 121.532871, 25.1248583 ], [ 121.5328331, 25.1248753 ], [ 121.5327919, 25.1248837 ], [ 121.5327496, 25.1248829 ],
          [ 121.5327088, 25.124873 ], [ 121.5326717, 25.1248545 ], [ 121.5326407, 25.1248285 ], [ 121.5326174, 25.1247965 ],
          [ 121.5326032, 25.1247605 ], [ 121.532599, 25.1247224 ], [ 121.532605, 25.1246845 ], [ 121.5326208, 25.124649 ],
          [ 121.5326456, 25.1246179 ], [ 121.5326778, 25.1245932 ], [ 121.5326382, 25.1244929 ], [ 121.5326326, 25.1244787 ],
          [ 121.532527, 25.12420 ]
        ],
        departure: [
          [ 121.532527, 25.12420 ], [ 121.5324218, 25.1239219 ], [ 121.532272341459, 25.1235273321679 ]
        ]
      }
    ].freeze
    SPIKE_RADIUS_METERS = 400.0
    LOOP_SNAP_METERS = 25.0

    # Neighbourhood street loops whose TDX shapes cut every corner differently.
    # The stretch of a route lying within `max_meters` of the loop is redrawn
    # along the loop from where it joins to where it leaves, in whichever
    # direction fits the original shape best (ties go the listed way round).
    # `loop` is closed and listed in the usual direction of travel (OSM roads).
    LOOP_CIRCULATIONS = [
      {
        # 南港花園社區: 福德街373巷 north past 花二, 福德街 over the top and down
        # past 花一／花五, then 福德街373巷 back past 花四／花三.
        name: "南港花園社區",
        max_meters: 60.0,
        # 成福路269巷 (south-west), 福德街 from the west, 東新街170巷 (north-east).
        junctions: [ [ 121.591642, 25.038727 ], [ 121.590613, 25.040366 ], [ 121.592897, 25.040417 ] ],
        loop: [
          [ 121.591642, 25.038727 ], [ 121.591580, 25.038753 ], [ 121.591496, 25.038788 ], [ 121.591423, 25.038866 ],
          [ 121.591370, 25.038941 ], [ 121.591329, 25.039071 ], [ 121.591296, 25.039322 ], [ 121.591282, 25.039365 ],
          [ 121.591214, 25.039579 ], [ 121.591096, 25.039928 ], [ 121.591069, 25.040023 ], [ 121.590956, 25.040148 ],
          [ 121.590707, 25.040306 ], [ 121.590613, 25.040366 ], [ 121.590632, 25.040415 ], [ 121.590683, 25.040545 ],
          [ 121.590747, 25.041108 ], [ 121.590792, 25.041217 ], [ 121.590860, 25.041290 ], [ 121.590984, 25.041329 ],
          [ 121.591012, 25.041334 ], [ 121.591124, 25.041352 ], [ 121.591381, 25.041334 ], [ 121.591493, 25.041303 ],
          [ 121.591559, 25.041257 ], [ 121.591631, 25.041155 ], [ 121.591770, 25.040845 ], [ 121.591940, 25.040333 ],
          [ 121.592020, 25.040154 ], [ 121.592135, 25.040043 ], [ 121.592242, 25.040005 ], [ 121.592352, 25.039995 ],
          [ 121.592508, 25.040047 ], [ 121.592607, 25.040104 ], [ 121.592679, 25.040155 ], [ 121.592782, 25.040264 ],
          [ 121.592855, 25.040361 ], [ 121.592897, 25.040417 ], [ 121.592994, 25.040312 ], [ 121.593430, 25.039842 ],
          [ 121.593467, 25.039800 ], [ 121.593483, 25.039712 ], [ 121.593483, 25.039511 ], [ 121.593485, 25.039251 ],
          [ 121.593457, 25.039137 ], [ 121.593382, 25.039043 ], [ 121.593287, 25.038967 ], [ 121.593156, 25.038890 ],
          [ 121.593034, 25.038858 ], [ 121.592533, 25.038808 ], [ 121.591728, 25.038735 ], [ 121.591642, 25.038727 ]
        ]
      }
    ].freeze

    module_function

    def process_collection!(data)
      return false unless data.is_a?(Hash)

      patches = PATCHES[data.dig("properties", "id")] || []
      excursions = EXCURSIONS[data.dig("properties", "id")] || []
      features = Array(data["features"])
      stations = features.select { |feature| feature.dig("properties", "feature_type") == "station" }
      changed = false
      features.each do |feature|
        next unless feature.dig("properties", "feature_type") == "route"
        next unless feature.dig("geometry", "type") == "LineString"

        direction = feature.dig("properties", "direction").to_s
        line = feature.dig("geometry", "coordinates")
        patched = line
        patches.each do |patch|
          patched = apply(patched, patch) if direction == patch[:direction].to_s
        end
        excursions.each do |excursion|
          patched = drop_excursion(patched, excursion[:anchor]) if direction == excursion[:direction].to_s
        end
        stations.each do |station|
          next unless station.dig("properties", "direction").to_s == direction

          circulation = STOP_CIRCULATIONS[station.dig("properties", "name")]
          patched = circulate(patched, station.dig("geometry", "coordinates"), circulation) if circulation
        end
        LOOP_CIRCULATIONS.each { |circulation| patched = loop_through(patched, circulation) }
        TERMINAL_APPROACHES.each { |terminal| patched = approach_terminal(patched, terminal) }
        TERMINAL_LOOPS.each { |terminal| patched = loop_terminal(patched, terminal) }
        next if patched == line

        feature["geometry"]["coordinates"] = patched
        changed = true
      end
      changed
    end

    def circulate(line, stop, circulation)
      min_lon, min_lat, max_lon, max_lat = circulation[:bounds]
      inside = ->(point) { point[0].between?(min_lon, max_lon) && point[1].between?(min_lat, max_lat) }

      runs = []
      index = 0
      while index < line.length
        unless inside.call(line[index])
          index += 1
          next
        end

        last = index
        last += 1 while last + 1 < line.length && inside.call(line[last + 1])
        runs << [ index, last ]
        index = last + 1
      end

      patched = line
      runs.reverse_each do |first, last|
        next if first.zero? || last + 1 >= line.length
        next if (first..last).none? { |i| meters_between(line[i], stop) <= circulation[:max_stop_meters] }
        next unless line[last + 1][0] < circulation[:west_of]

        side = line[first - 1][0] < circulation[:west_of] ? :west : :east
        path = circulation[:paths][side]
        next if patched[first..last] == path

        patched = patched[0...first] + path.map(&:dup) + patched[(last + 1)..]
      end
      patched == line ? line : remove_spikes(patched, stop)
    end

    def loop_through(line, circulation)
      loop_line = circulation[:loop]
      margin = circulation[:max_meters] / 100_000.0
      lons, lats = loop_line.transpose
      return line unless line.any? { |lon, lat|
        lon.between?(lons.min - margin, lons.max + margin) && lat.between?(lats.min - margin, lats.max + margin)
      }

      near = line.map { |point| loop_projection(loop_line, point)[:distance] <= circulation[:max_meters] }
      return line unless near.any?

      result = []
      index = 0
      changed = false
      while index < line.length
        unless near[index]
          result << line[index]
          index += 1
          next
        end

        last = index
        last += 1 while last + 1 < line.length && near[last + 1]
        run = line[index..last]
        path = loop_path(circulation, run)
        if path && path != run
          result.concat(path)
          changed = true
        else
          result.concat(run)
        end
        index = last + 1
      end
      changed ? result : line
    end

    # The loop stretch between where `run` joins and leaves it, going whichever
    # way round stays closest to `run`.
    def loop_path(circulation, run)
      loop_line = circulation[:loop]
      entry = snap_to_junction(circulation, loop_projection(loop_line, run.first))
      exit = snap_to_junction(circulation, loop_projection(loop_line, run.last))
      total = Geojson::BusShapeTrimmer.path_length(loop_line)
      forward = loop_walk(loop_line, entry, exit, total, :forward)
      backward = loop_walk(loop_line, entry, exit, total, :backward)
      return nil if Geojson::BusShapeTrimmer.path_length(forward) < 1.0 && Geojson::BusShapeTrimmer.path_length(run) < 1.0

      candidates = [ forward, backward ]
      candidates << loop_walk(loop_line, entry, exit, total, :forward, extra_lap: true) if (exit[:at] - entry[:at]) % total < LOOP_SNAP_METERS * 2
      candidates.min_by { |path| (fit_error(path, run) * 10).round }
    end

    def loop_walk(loop_line, from, to, total, way, extra_lap: false)
      offsets = []
      position = 0.0
      loop_line.each_cons(2) do |a, b|
        offsets << [ position, a ]
        position += meters_between(a, b)
      end
      span = way == :forward ? (to[:at] - from[:at]) % total : (from[:at] - to[:at]) % total
      span += total if extra_lap
      laps = extra_lap ? [ 0.0, total ] : [ 0.0 ]
      between = offsets.flat_map do |at, point|
        offset = way == :forward ? (at - from[:at]) % total : (from[:at] - at) % total
        laps.filter_map { |lap| [ offset + lap, point.dup ] if (offset + lap).positive? && offset + lap < span }
      end
      [ from[:point] ] + between.sort_by(&:first).map(&:last) + [ to[:point] ]
    end

    def loop_projection(loop_line, point)
      best = nil
      position = 0.0
      loop_line.each_cons(2) do |a, b|
        projection = Geojson::BusShapeTrimmer.project(point, a, b)
        if best.nil? || projection[:distance] < best[:distance]
          best = { distance: projection[:distance], point: projection[:point], at: position + meters_between(a, projection[:point]) }
        end
        position += meters_between(a, b)
      end
      best
    end

    # Joins and leaves happen at the loop's junctions; snapping there avoids a
    # short back-and-forth jog where the projection lands just past the corner.
    def snap_to_junction(circulation, projection)
      junction = circulation[:junctions]
        .map { |point| [ point, meters_between(point, projection[:point]) ] }
        .select { |_, gap| gap <= LOOP_SNAP_METERS }
        .min_by(&:last)&.first
      return projection unless junction

      loop_projection(circulation[:loop], junction).merge(point: junction.dup)
    end

    # Mean distance from the original stretch to a candidate path, both ways
    # round, so a path that skips part of the stretch scores badly too.
    def fit_error(path, run)
      to_path = run.sum { |point| distance_to_line(path, point) } / run.length
      to_run = path.sum { |point| distance_to_line(run, point) } / path.length
      to_path + to_run
    end

    def distance_to_line(line, point)
      return meters_between(line.first, point) if line.length < 2

      line.each_cons(2).map { |a, b| Geojson::BusShapeTrimmer.project(point, a, b)[:distance] }.min
    end

    # Drop A → B → A out-and-back jogs (shape noise at the hub entrances).
    def remove_spikes(line, center)
      result = line.dup
      index = 1
      while index < result.length - 1
        if meters_between(result[index], center) <= SPIKE_RADIUS_METERS &&
            meters_between(result[index - 1], result[index + 1]) < 2.0 &&
            meters_between(result[index - 1], result[index]) > 5.0
          result.slice!(index, 2)
          index = [ index - 1, 1 ].max
        else
          index += 1
        end
      end
      result
    end

    def drop_excursion(line, anchor)
      near = line.each_index.select { |index| meters_between(line[index], anchor) <= EXCURSION_ANCHOR_METERS }
      first = near.first
      last = near.last
      return line if first.nil? || last == first || last + 1 >= line.length
      return line if Geojson::BusShapeTrimmer.path_length(line[first..last]) < MIN_EXCURSION_METERS

      line[0..first] + line[(last + 1)..]
    end

    def approach_terminal(line, terminal)
      return line if line.length < 2
      return line if meters_between(line[-1], terminal[:departure]) > terminal[:departure_meters]
      return line if meters_between(line[-2], terminal[:arrival]) > terminal[:arrival_meters]

      line[0..-2] + terminal[:path].map(&:dup) + [ line[-1] ]
    end

    def loop_terminal(line, terminal)
      return line if line.length < 2

      near_entry = ->(index) { meters_between(line[index], terminal[:arrival].first) <= terminal[:join_meters] }
      near_exit = ->(index) { meters_between(line[index], terminal[:departure].last) <= terminal[:join_meters] }

      if meters_between(line.last, terminal[:stop]) <= terminal[:stop_meters]
        last = (line.length - 1).downto(0).find { |index| near_entry.call(index) }
        if last
          first = last
          first -= 1 while first.positive? && near_entry.call(first - 1)
          line = line[0...first] + terminal[:arrival].map(&:dup)
        end
      end

      if meters_between(line.first, terminal[:stop]) <= terminal[:stop_meters]
        first = (0...line.length).find { |index| near_exit.call(index) }
        if first
          last = first
          last += 1 while last + 1 < line.length && near_exit.call(last + 1)
          line = terminal[:departure].map(&:dup) + line[(last + 1)..]
        end
      end

      line
    end

    def apply(line, patch)
      from = line.index { |point| meters_between(point, patch[:from]) <= VERTEX_MATCH_METERS }
      return line unless from

      to = (from + 1...line.length).find { |index| meters_between(line[index], patch[:to]) <= VERTEX_MATCH_METERS }
      return line unless to

      line[0..from] + patch[:path].map(&:dup) + line[to..]
    end

    def meters_between(left, right)
      Geojson::BusLoopCloser.meters_between(left, right)
    end
  end
end
