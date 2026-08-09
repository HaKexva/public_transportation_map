# frozen_string_literal: true

module Transit
  class VehiclePositionQuery
    DEFAULT_WINDOW_MINUTES = 180
    MAX_CANDIDATE_TRIPS = 2500
    HEADWAY_TRAVEL_MIN_PER_SEGMENT = 2
    DEFAULT_LOOP_SPACING_MINUTES = 5
    METRO_SEGMENT_FALLBACK_MINUTES = 2.5
    # Civil times before this hour still use the previous calendar day's service.
    SERVICE_DAY_ROLLOVER_HOUR = 3
    CLOCK_ZONE = ActiveSupport::TimeZone["Taipei"]
    METRO_SYSTEMS = %w[
      taipei_metro
      new_taipei_metro
      taoyuan_metro
      taichung_metro
      kaohsiung_metro
    ].freeze

    # Prefer the line's own station-number prefix when stop_sequence is wrong
    # (imported transfer stations are often appended out of geographic order).
    ROUTE_LINE_PREFIX = {
      "bannan" => "BL",
      "tamsui_xinyi" => "R",
      "xinbeitou_branch" => "R",
      "songshan_xindian" => "G",
      "xiaobitan_branch" => "G",
      "zhonghe_xinlu" => "O",
      "wenhu_line" => "BR",
      "circular" => "Y",
      "danhai_lrt" => "V",
      "ankeng_lrt" => "K",
      "sanying_line" => "LB",
      "airport_mrt" => "A",
      "airport_mrt_express" => "A"
    }.freeze

    def initialize(at:, route_ids:, datasets: ScheduleDataset.active.to_a)
      @at = at.in_time_zone(CLOCK_ZONE)
      @route_ids = Array(route_ids).map(&:to_s).reject(&:blank?)
      @datasets = datasets
      @live_meta = { applied: false, tra: false, metro: false, gps: false }
    end

    attr_reader :live_meta

    def call
      return [] if @route_ids.empty? || @datasets.blank?

      # Never cache final positions — progress must change every second while playing.
      # Heavy board extracts are cached separately inside compute.
      compute_vehicles(service_date_for(@at))
    end

    private

    MULTI_STOP_SYSTEMS = %w[tra hsr sugar_railway other].freeze

    # Late-night scrubbing (00:00–03:00) still belongs to the previous operating day.
    def service_date_for(at)
      local = at.in_time_zone(CLOCK_ZONE)
      return local.to_date if local.hour >= SERVICE_DAY_ROLLOVER_HOUR

      local.to_date - 1
    end

    def compute_vehicles(at_date)
      calendar_ids = Transit::ServiceCalendarResolver.calendar_ids_for_date(at_date)
      return [] if calendar_ids.empty?

      routes = TransitRoute.where(route_id: @route_ids).to_a
      preload_metro_boards!(routes, calendar_ids: calendar_ids, at_date: at_date)

      vehicles = []
      routes.each do |route|
        vehicle_directions_for_route(route).each do |direction|
          vehicles.concat vehicles_for_route_direction(route, direction, calendar_ids: calendar_ids)
        end
      end

      overlay = Transit::LiveVehicleOverlay.new(at: @at, route_ids: @route_ids)
      overlay.apply!(vehicles)
      @live_meta = overlay.meta.merge(
        near_now: overlay.near_now?,
        configured: Transit::TdxClient.configured?
      )
      vehicles
    end

    def preload_metro_boards!(routes, calendar_ids:, at_date:)
      metro_routes = routes.select { |route| metro_system?(route) }
      @metro_boards_by_route_dir = {}
      return if metro_routes.empty?

      cache_key = [
        "metro_boards/all/v3",
        at_date.iso8601,
        calendar_ids.sort.join(",")
      ]

      all_boards = Rails.cache.fetch(cache_key, expires_in: 30.minutes) do
        metro_ids = TransitRoute.where(system_id: METRO_SYSTEMS).pluck(:id)
        load_metro_boards(metro_ids, calendar_ids)
      end

      route_db_ids = metro_routes.map(&:id).to_set
      @metro_boards_by_route_dir = all_boards.select { |(route_db_id, _direction), _rows| route_db_ids.include?(route_db_id) }
    end

    def load_metro_boards(route_db_ids, calendar_ids)
      rows = TripStopTime.joins(:schedule_trip).where(
        schedule_trips: {
          transit_route_id: route_db_ids,
          service_calendar_id: calendar_ids
        }
      ).where.not(schedule_trips: { destination_name: [ nil, "" ] }).pluck(
        "schedule_trips.transit_route_id",
        "schedule_trips.direction",
        :station_ref,
        Arel.sql("COALESCE(trip_stop_times.departure_time, trip_stop_times.arrival_time)"),
        "schedule_trips.train_number",
        "schedule_trips.destination_name"
      )

      grouped = {}
      rows.each do |route_db_id, direction, station_ref, pass_time, train_number, destination|
        key = [ route_db_id, direction ]
        (grouped[key] ||= []) << [ station_ref, pass_time, train_number, destination ]
      end
      grouped
    end

    def vehicle_directions_for_route(route)
      trip_dirs = ScheduleTrip.where(transit_route_id: route.id).distinct.limit(8).pluck(:direction).compact.uniq
      dirs = trip_dirs
      if dirs.empty?
        headway_dirs = HeadwayRule.where(transit_route_id: route.id).distinct.pluck(:direction).compact.uniq
        dirs = headway_dirs
      end

      if dirs.empty?
        return route.transit_route_stations.exists? ? %w[outbound inbound] : []
      end

      dirs |= [ "inbound" ] if dirs.include?("outbound")
      dirs |= [ "outbound" ] if dirs.include?("inbound")
      dirs |= [ "reverse" ] if dirs.include?("forward")
      dirs |= [ "forward" ] if dirs.include?("reverse")
      dirs.first(2)
    end

    def vehicles_for_route_direction(route, direction, calendar_ids:)
      if metro_system?(route)
        metro = station_timetable_vehicles_for(route, direction, calendar_ids: calendar_ids)
        return metro if metro.any?

        # Only if station timetables are missing — headway / synthetic as last resort.
        headway = headway_vehicles_for(route, direction, calendar_ids: calendar_ids)
        return headway if headway.any?

        return synthetic_looping_vehicles(route, direction)
      end

      if multi_stop_worth_trying?(route)
        multi_stop = multi_stop_vehicles_for(route, direction, calendar_ids: calendar_ids)
        return multi_stop unless multi_stop.empty?
      end

      headway = headway_vehicles_for(route, direction, calendar_ids: calendar_ids)
      return headway if headway.any?

      synthetic_looping_vehicles(route, direction)
    end

    def metro_system?(route)
      METRO_SYSTEMS.include?(route.system_id.to_s)
    end

    def multi_stop_worth_trying?(route)
      MULTI_STOP_SYSTEMS.include?(route.system_id.to_s)
    end

    # Rebuild in-service metro trains from per-station departure boards:
    # a departure at station i that has not yet "appeared" at station i+1 is on that segment.
    def station_timetable_vehicles_for(route, direction, calendar_ids:)
      stations = ordered_route_stations(route, direction)
      return [] if stations.length < 2

      rows = @metro_boards_by_route_dir&.dig([ route.id, direction ])
      if rows.nil?
        rows = TripStopTime.joins(:schedule_trip).where(
          schedule_trips: {
            transit_route_id: route.id,
            direction: direction,
            service_calendar_id: calendar_ids
          }
        ).where.not(schedule_trips: { destination_name: [ nil, "" ] }).pluck(
          :station_ref,
          Arel.sql("COALESCE(trip_stop_times.departure_time, trip_stop_times.arrival_time)"),
          "schedule_trips.train_number",
          "schedule_trips.destination_name"
        )
      end

      return [] if rows.empty?

      at_minutes = minutes_since_midnight(@at)
      terminal_names = [ stations.first.name, stations.last.name ].compact.uniq
      by_destination = rows.group_by { |row| row[3] }

      by_destination.flat_map do |destination, dest_rows|
        metro_vehicles_from_rows(
          route: route,
          direction: direction,
          destination: destination,
          stations: stations,
          rows: dest_rows,
          at_minutes: at_minutes,
          short_turn: short_turn_destination?(destination, terminal_names)
        )
      end
    end

    def short_turn_destination?(destination, terminal_names)
      name = destination.to_s.strip
      return false if name.blank?
      return true if name.match?(/區間|短駛|不載客/)

      terminal_names.none? { |terminal| terminal.to_s.include?(name) || name.include?(terminal.to_s) }
    end

    def metro_vehicles_from_rows(route:, direction:, destination:, stations:, rows:, at_minutes:, short_turn:)
      deps_by_key = Hash.new { |h, k| h[k] = [] }
      rows.each do |station_ref, pass_time, train_number, _destination|
        key = station_match_key(route, station_ref)
        next unless key

        deps_by_key[key] << {
          minutes: minutes_since_midnight(pass_time),
          train_number: train_number,
          station_ref: station_ref
        }
      end
      deps_by_key.each_value { |list| list.sort_by! { |row| row[:minutes] } }

      active_stations = stations
      if short_turn
        dest_idx = stations.index { |station| station.name.to_s.include?(destination.to_s) || destination.to_s.include?(station.name.to_s) }
        active_stations = stations[0..dest_idx] if dest_idx && dest_idx >= 1
      end

      label = short_turn ? "往#{destination}" : destination.to_s
      dwell_minutes = 0.35
      vehicles = []

      # Build one vehicle per "wave" currently on the line by walking each departure
      # at every station and pairing it with the next station board (no cross-segment
      # double count: only emit while between from-dep and to-dep / dwell).
      active_stations.each_cons(2).with_index do |(from_station, to_station), index|
        from_key = station_match_key(route, from_station.station_ref)
        to_key = station_match_key(route, to_station.station_ref)
        next unless from_key && to_key

        from_deps = deps_by_key[from_key]
        to_deps = deps_by_key[to_key]
        next if from_deps.empty?

        used_to = {}
        from_deps.each do |departure|
          # Skip future / stale departures (wrap-safe): only hops that left within ~20 min.
          age = wrapped_minute_span(departure[:minutes], at_minutes)
          next if age > (20 + dwell_minutes)

          matched_idx = to_deps.find_index.with_index do |candidate, idx|
            next false if used_to[idx]

            gap = wrapped_minute_span(departure[:minutes], candidate[:minutes])
            gap.positive? && gap <= 20
          end

          if matched_idx
            used_to[matched_idx] = true
            arrival_minutes = to_deps[matched_idx][:minutes]
          else
            arrival_minutes = normalize_to_0_1440(departure[:minutes] + METRO_SEGMENT_FALLBACK_MINUTES)
          end

          span = wrapped_minute_span(departure[:minutes], arrival_minutes)
          next if span <= 0

          dwell_end = normalize_to_0_1440(arrival_minutes + dwell_minutes)

          # Prefer dwell at the arrival instant so the next hop owns progress=0.
          if at_minutes != arrival_minutes &&
              within_segment_minutes?(at_minutes, departure[:minutes], arrival_minutes)
            progress = segment_progress_minutes(at_minutes, departure[:minutes], arrival_minutes)
            stopped = false
            dep_edge = departure[:minutes]
            arr_edge = arrival_minutes
          elsif dwell_minutes.positive? &&
              (at_minutes == arrival_minutes ||
                within_segment_minutes?(at_minutes, arrival_minutes, dwell_end))
            progress = 1.0
            stopped = true
            dep_edge = arrival_minutes
            arr_edge = dwell_end
          else
            next
          end

          # Stable-ish id: destination wave + departure clock (survives while on this hop;
          # client soft-matches across hops for smooth handoff).
          vehicle = {
            id: "metro:#{route.id}:#{direction}:#{destination}:#{from_key}:#{departure[:minutes].round(2)}",
            soft_id: "metro:#{route.id}:#{direction}:#{destination}:#{departure[:minutes].round(1)}",
            train_number: departure[:train_number],
            label: label,
            route_id: route.route_id,
            system_id: route.system_id,
            color: route.color,
            from_station_ref: from_station.station_ref,
            to_station_ref: to_station.station_ref,
            progress: progress.round(4),
            delay_seconds: 0,
            status: stopped ? "stopped" : "on_time",
            destination_name: destination,
            from_station_name: from_station.name,
            to_station_name: to_station.name,
            position_source: "station_timetable",
            delay_source: "none",
            direction: direction,
            segment_index: index,
            departure_minutes: dep_edge,
            arrival_minutes: arr_edge,
            motion_departure_minutes: departure[:minutes],
            motion_arrival_minutes: arrival_minutes,
            service_kind: short_turn ? "short_turn" : "through",
            path: metro_wave_path(active_stations, deps_by_key, route, departure)
          }
          vehicles << attach_coordinates(route, vehicle)
        end
      end

      vehicles
    end

    def attach_coordinates(route, vehicle)
      vehicle[:from_station_name] ||= Transit::GeojsonStationCoords.lookup_name(route, vehicle[:from_station_ref])
      vehicle[:to_station_name] ||= Transit::GeojsonStationCoords.lookup_name(route, vehicle[:to_station_ref])

      coords = Transit::GeojsonStationCoords.interpolate(
        route,
        vehicle[:from_station_ref],
        vehicle[:to_station_ref],
        vehicle[:progress]
      )
      return vehicle unless coords

      vehicle.merge(coords)
    end

    def station_match_key(route, station_ref)
      prefix = line_prefix_for(route)
      number = station_line_number(station_ref, prefix) if prefix
      return format("%s%02d", prefix, number) if prefix && number

      station_ref.to_s.split(";").map(&:strip).reject(&:blank?).first
    end

    # Uses real timetable stop sequences to interpolate vehicle progress along the line.
    def multi_stop_vehicles_for(route, direction, calendar_ids:)
      start_time, end_time = time_window_around(@at, minutes: DEFAULT_WINDOW_MINUTES)

      candidates = ScheduleTrip.joins(:trip_stop_times)
        .where(transit_route_id: route.id, direction: direction, service_calendar_id: calendar_ids)
        .where(pass_time_between_sql(start_time, end_time), start_time: start_time, end_time: end_time)
        .distinct
        .limit(MAX_CANDIDATE_TRIPS)
        .pluck(:id, :train_number, :destination_name, :notes)

      return [] if candidates.empty?

      trip_meta = {}
      trip_ids = candidates.map do |id, train_number, destination_name, notes|
        trip_meta[id] = { train_number: train_number, destination_name: destination_name, notes: notes }
        id
      end

      stop_rows = TripStopTime.where(schedule_trip_id: trip_ids).pluck(
        :schedule_trip_id,
        :stop_sequence,
        :station_ref,
        :arrival_time,
        :departure_time
      )

      stops_by_trip = {}
      stop_rows.each do |trip_id, stop_sequence, station_ref, arrival_time, departure_time|
        (stops_by_trip[trip_id] ||= []) << {
          sequence: stop_sequence,
          station_ref: station_ref,
          arrival: minutes_since_midnight(arrival_time || departure_time),
          departure: minutes_since_midnight(departure_time || arrival_time)
        }
      end
      stops_by_trip.each_value { |list| list.sort_by! { |row| row[:sequence] } }

      effective_at_minutes = minutes_since_midnight(@at)
      vehicles = []

      trip_ids.each do |trip_id|
        ordered = stops_by_trip[trip_id]
        next if ordered.nil? || ordered.length < 2

        segment = find_active_trip_placement(ordered, effective_at_minutes)
        next unless segment

        from_ref, to_ref, segment_progress, departure_minutes, arrival_minutes, stopped = segment
        meta = trip_meta[trip_id]
        train_no = meta[:train_number].to_s

        vehicle = {
          id: "trip:#{trip_id}",
          soft_id: "trip:#{trip_id}",
          train_number: train_no,
          label: train_no.presence || route_label_for(route),
          route_id: route.route_id,
          system_id: route.system_id,
          color: route.color,
          from_station_ref: from_ref,
          to_station_ref: to_ref,
          progress: segment_progress.round(4),
          delay_seconds: 0,
          status: stopped ? "stopped" : "on_time",
          destination_name: meta[:destination_name],
          from_station_name: nil,
          to_station_name: nil,
          position_source: "timetable",
          delay_source: "none",
          direction: direction,
          departure_minutes: departure_minutes,
          arrival_minutes: arrival_minutes,
          motion_departure_minutes: departure_minutes,
          motion_arrival_minutes: arrival_minutes,
          service_kind: "through",
          path: compact_stop_path(ordered)
        }
        attach_continuation!(vehicle, trip_id: trip_id, meta: meta, ordered: ordered, to_ref: to_ref, calendar_ids: calendar_ids)
        vehicles << attach_coordinates(route, vehicle)
      end

      vehicles
    end

    def compact_stop_path(ordered)
      Array(ordered).filter_map do |stop|
        ref = stop[:station_ref].to_s
        next if ref.blank?

        {
          r: ref,
          a: stop[:arrival].to_f.round(3),
          d: stop[:departure].to_f.round(3)
        }
      end
    end

    def metro_wave_path(active_stations, deps_by_key, route, departure)
      train_no = departure[:train_number].to_s
      return nil if train_no.blank?

      last_min = nil
      path = active_stations.filter_map do |station|
        key = station_match_key(route, station.station_ref)
        next unless key

        candidates = deps_by_key[key].select { |row| row[:train_number].to_s == train_no }
        hit = if last_min
          candidates.find { |row|
            gap = wrapped_minute_span(last_min, row[:minutes])
            gap.positive? && gap <= 25
          }
        else
          candidates.min_by { |row|
            ahead = wrapped_minute_span(departure[:minutes], row[:minutes])
            behind = wrapped_minute_span(row[:minutes], departure[:minutes])
            [ ahead, behind ].min
          }
        end
        next unless hit

        last_min = hit[:minutes]
        {
          r: station.station_ref,
          a: hit[:minutes].round(3),
          d: hit[:minutes].round(3),
          n: station.name
        }
      end

      path.length >= 2 ? path : nil
    end

    def attach_continuation!(vehicle, trip_id:, meta:, ordered:, to_ref:, calendar_ids:)
      return unless Transit::TrainContinuation.relevant_system?(vehicle[:system_id])

      last = ordered.last
      return unless last && Transit::TrainContinuation.same_station?(to_ref, last[:station_ref])

      continues_as = continuation_finder(calendar_ids).lookup(
        trip_id: trip_id,
        train_number: meta[:train_number],
        last_station_ref: last[:station_ref],
        arrival_minutes: last[:arrival],
        notes: meta[:notes]
      )
      vehicle[:continues_as] = continues_as if continues_as
    end

    def continuation_finder(calendar_ids)
      @continuation_finder ||= Transit::TrainContinuation.new(calendar_ids: calendar_ids)
    end

    # Returns [from_ref, to_ref, progress, dep_minutes, arr_minutes, stopped]
    def find_active_trip_placement(ordered_stops, effective_at_minutes)
      minutes = normalize_to_0_1440(effective_at_minutes)

      ordered_stops.each_with_index do |stop, i|
        # Dwell at this station between arrival and departure.
        if stop[:arrival] <= stop[:departure]
          if minutes >= stop[:arrival] && minutes < stop[:departure]
            next_stop = ordered_stops[i + 1] || stop
            return [ stop[:station_ref], next_stop[:station_ref], 0.0, stop[:arrival], stop[:departure], true ]
          end
        end

        next_stop = ordered_stops[i + 1]
        next unless next_stop

        a = stop[:departure]
        b = next_stop[:arrival]
        if within_segment_minutes?(minutes, a, b)
          return [ stop[:station_ref], next_stop[:station_ref], segment_progress_minutes(minutes, a, b), a, b, false ]
        end
      end

      nil
    end

    def headway_vehicles_for(route, direction, calendar_ids:)
      station_records = ordered_route_stations(route, direction)
      return [] if station_records.length < 2

      headway_rules = HeadwayRule.where(
        transit_route_id: route.id,
        direction: direction,
        service_calendar_id: calendar_ids
      ).order(:starts_at)

      # If this direction has no rules, reuse the opposite direction's window as a tempo hint.
      if headway_rules.empty?
        opposite = opposite_direction(direction)
        headway_rules = HeadwayRule.where(
          transit_route_id: route.id,
          direction: opposite,
          service_calendar_id: calendar_ids
        ).order(:starts_at) if opposite
      end

      return [] if headway_rules.empty?

      rule = headway_rule_containing_time(headway_rules, minutes_since_midnight(@at)) || headway_rules.first
      spacing_minutes = [ (rule.interval_seconds.to_f / 60.0), 2.0 ].max

      build_looping_vehicles(
        route: route,
        direction: direction,
        station_records: station_records,
        departure_anchor: rule.first_departure || rule.starts_at,
        id_prefix: "headway:#{route.id}:#{direction}:#{rule.id}",
        spacing_minutes: spacing_minutes,
        position_source: "headway_estimate"
      )
    end

    def synthetic_looping_vehicles(route, direction)
      station_records = ordered_route_stations(route, direction)
      return [] if station_records.length < 2

      build_looping_vehicles(
        route: route,
        direction: direction,
        station_records: station_records,
        departure_anchor: Time.utc(2000, 1, 1, 6, 0, 0),
        id_prefix: "synth:#{route.id}:#{direction}",
        spacing_minutes: DEFAULT_LOOP_SPACING_MINUTES,
        position_source: "schedule_unavailable"
      )
    end

    def build_looping_vehicles(route:, direction:, station_records:, departure_anchor:, id_prefix:, spacing_minutes:, position_source:)
      travel_minutes = (station_records.length - 1) * HEADWAY_TRAVEL_MIN_PER_SEGMENT
      return [] if travel_minutes <= 0

      count = [ (travel_minutes / spacing_minutes).floor, 1 ].max
      # Show a full circulating fleet for headway-only lines (e.g. 文湖線).
      count = [ count, 80 ].min

      at_minutes = minutes_since_midnight(@at)
      delay_seconds = 0
      status = "on_time"
      effective_at_minutes = at_minutes
      rule_departure_minutes = minutes_since_midnight(departure_anchor)
      label = route_label_for(route)

      (0...count).map do |slot|
        slot_offset = slot * (travel_minutes / count.to_f)
        elapsed = modulo_minutes(effective_at_minutes - rule_departure_minutes - slot_offset, travel_minutes)
        route_progress = (elapsed / travel_minutes).clamp(0.0, 1.0)

        from_idx = [ (route_progress * (station_records.length - 1)).floor, station_records.length - 2 ].min
        to_idx = from_idx + 1
        segment_start = from_idx.to_f / (station_records.length - 1)
        segment_end = to_idx.to_f / (station_records.length - 1)
        segment_progress =
          if (segment_end - segment_start).abs < 1e-9
            0.0
          else
            ((route_progress - segment_start) / (segment_end - segment_start)).clamp(0.0, 1.0)
          end

        from_station = station_records[from_idx]
        to_station = station_records[to_idx]

        attach_coordinates(route, {
          id: "#{id_prefix}:#{slot}",
          train_number: "#{route.route_id}-SIM-#{direction}-#{slot}",
          label: station_records.last.name.presence || label,
          route_id: route.route_id,
          system_id: route.system_id,
          color: route.color,
          from_station_ref: from_station.station_ref,
          to_station_ref: to_station.station_ref,
          progress: segment_progress.round(4),
          delay_seconds: delay_seconds,
          status: status,
          destination_name: station_records.last.name,
          from_station_name: from_station.name,
          to_station_name: to_station.name,
          position_source: position_source,
          delay_source: "none",
          direction: direction,
          service_kind: "through"
        })
      end
    end

    def route_label_for(route)
      name = route.name.to_s
      return "高鐵" if route.system_id.to_s == "hsr" || route.route_id.to_s.include?("hsr")

      # 「板南線」→「板南」；「淡海輕軌」→「淡海」
      shortened = name.sub(/（.*?）/, "").sub(/線\z/, "").sub(/輕軌\z/, "").sub(/捷運\z/, "").strip
      return shortened[0, 2] if shortened.match?(/\p{Han}/)

      route.route_id.to_s.split("_").first.to_s[0, 4].upcase.presence || "TRA"
    end

    def opposite_direction(direction)
      case direction.to_s
      when "outbound" then "inbound"
      when "inbound" then "outbound"
      when "forward" then "reverse"
      when "reverse" then "forward"
      else nil
      end
    end

    def headway_rule_containing_time(headway_rules, at_minutes)
      headway_rules.find do |rule|
        start_min = minutes_since_midnight(rule.starts_at)
        end_min = minutes_since_midnight(rule.ends_at)

        if start_min <= end_min
          at_minutes >= start_min && at_minutes <= end_min
        else
          at_minutes >= start_min || at_minutes <= end_min
        end
      end
    end

    def ordered_route_stations(route, direction)
      preferred = route.transit_route_stations.for_direction(direction).ordered.to_a
      base =
        if preferred.any?
          preferred
        else
          route.transit_route_stations.for_direction("both").ordered.to_a
        end

      sorted = sort_stations_along_line(route, base)
      return sorted.reverse if direction.to_s == "inbound" || direction.to_s == "reverse"

      sorted
    end

    def sort_stations_along_line(route, stations)
      return stations if stations.length < 2

      prefix = line_prefix_for(route)
      return stations unless prefix

      keyed = stations.map do |station|
        number = station_line_number(station.station_ref, prefix)
        [ number || 1_000_000, station.stop_sequence.to_i, station ]
      end

      # Only rewrite order when enough stations carry the line prefix.
      prefixed = keyed.count { |number, _, _| number < 1_000_000 }
      return stations if prefixed < 2

      keyed.sort_by { |number, seq, _| [ number, seq ] }.map(&:last)
    end

    def line_prefix_for(route)
      ROUTE_LINE_PREFIX[route.route_id.to_s] || infer_line_prefix(route)
    end

    def infer_line_prefix(route)
      counts = Hash.new(0)
      route.transit_route_stations.limit(40).pluck(:station_ref).each do |ref|
        ref.to_s.split(";").each do |part|
          match = part.strip.match(/\A([A-Z]+)\d/)
          counts[match[1]] += 1 if match
        end
      end
      counts.max_by { |_, count| count }&.first
    end

    def station_line_number(station_ref, prefix)
      station_ref.to_s.split(";").each do |part|
        match = part.strip.match(/\A#{Regexp.escape(prefix)}(\d+)\z/i)
        return match[1].to_i if match
      end
      nil
    end

    def within_segment_minutes?(minutes, a, b)
      if a <= b
        minutes >= a && minutes <= b
      else
        # wraps over midnight
        minutes >= a || minutes <= b
      end
    end

    # Forward minutes from `from` to `to` on a 24h clock (0 when equal).
    def wrapped_minute_span(from, to)
      normalize_to_0_1440(to.to_f - from.to_f)
    end

    def segment_progress_minutes(minutes, a, b)
      return 0.0 if a == b

      if a <= b
        segment_len = b - a
        offset = minutes - a
      else
        segment_len = (1440 - a) + b
        offset = minutes >= a ? (minutes - a) : (1440 - a + minutes)
      end

      (offset.to_f / segment_len.to_f).clamp(0.0, 1.0)
    end

    def pass_time_between_sql(start_time, end_time)
      # We can't rely on simple BETWEEN for cyclic time windows; build wrap-safe expression:
      # - if start <= end -> BETWEEN
      # - else -> >= start OR <= end
      start_min = minutes_since_midnight(start_time)
      end_min = minutes_since_midnight(end_time)

      if start_min <= end_min
        "COALESCE(trip_stop_times.departure_time, trip_stop_times.arrival_time) BETWEEN :start_time AND :end_time"
      else
        "COALESCE(trip_stop_times.departure_time, trip_stop_times.arrival_time) >= :start_time OR COALESCE(trip_stop_times.departure_time, trip_stop_times.arrival_time) <= :end_time"
      end
    end

    def time_window_around(time, minutes:)
      at_min = minutes_since_midnight(time)
      start_min = modulo_minutes(at_min - minutes, 1440)
      end_min = modulo_minutes(at_min + minutes, 1440)

      [ time_of_day_from_minutes(start_min), time_of_day_from_minutes(end_min) ]
    end

    def modulo_minutes(value, mod)
      ((value % mod) + mod) % mod
    end

    def normalize_to_0_1440(minutes)
      modulo_minutes(minutes, 1440)
    end

    def minutes_since_midnight(time_or_nil)
      return 0 unless time_or_nil

      # Schedule `time` columns are stored without timezone and round-trip as
      # TimeWithZone on dummy date 2000-01-01 tagged UTC — those hour/min values
      # already are Taiwan wall-clock and must not be shifted to Taipei again.
      if time_or_nil.is_a?(ActiveSupport::TimeWithZone) && time_or_nil.year != 2000
        t = time_or_nil.in_time_zone(CLOCK_ZONE)
        return t.hour * 60 + t.min + (t.sec / 60.0)
      end

      t = time_or_nil.respond_to?(:utc) ? time_or_nil.utc : time_or_nil
      t.hour * 60 + t.min + (t.sec / 60.0)
    end

    def time_of_day_from_minutes(minutes)
      m = minutes.to_i
      hour = m / 60
      min = m % 60
      # Use UTC Time so PostgreSQL `time without time zone` comparisons keep clock values.
      Time.utc(2000, 1, 1, hour, min, 0)
    end
  end
end
