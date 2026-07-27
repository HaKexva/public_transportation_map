# frozen_string_literal: true

module Transit
  class VehiclePositionQuery
    DEFAULT_WINDOW_MINUTES = 180
    MAX_CANDIDATE_TRIPS = 250
    MAX_VEHICLES_PER_ROUTE_DIRECTION = 3
    HEADWAY_TRAVEL_MIN_PER_SEGMENT = 2
    CLOCK_ZONE = ActiveSupport::TimeZone["Taipei"]

    def initialize(at:, route_ids:, datasets: ScheduleDataset.active.to_a)
      @at = at.in_time_zone(CLOCK_ZONE)
      @route_ids = Array(route_ids).map(&:to_s).reject(&:blank?)
      @datasets = datasets
    end

    def call
      return [] if @route_ids.empty? || @datasets.nil? || @datasets.empty?

      at_date = @at.to_date
      # We intentionally do not restrict to `ScheduleDataset.active`.
      # Some route data may exist only in older imports yet still be valid for visualization.
      calendar_ids = Transit::ServiceCalendarResolver.calendar_ids_for_date(at_date)
      return [] if calendar_ids.empty?

      routes = TransitRoute.where(route_id: @route_ids)

      vehicles = []
      routes.find_each do |route|
        directions = vehicle_directions_for_route(route).first(2)
        directions.each do |direction|
          vehicles.concat vehicles_for_route_direction(route, direction, calendar_ids: calendar_ids)
          vehicles = vehicles.first(200) # hard cap for safety
        end
      end

      vehicles
    end

    private

    def vehicle_directions_for_route(route)
      headway_directions = HeadwayRule.where(transit_route_id: route.id).distinct.pluck(:direction)
      trip_directions = ScheduleTrip.where(transit_route_id: route.id).distinct.pluck(:direction)
      (headway_directions + trip_directions).compact.uniq
    end

    def vehicles_for_route_direction(route, direction, calendar_ids:)
      multi_stop = multi_stop_vehicles_for(route, direction, calendar_ids: calendar_ids)
      return multi_stop unless multi_stop.empty?

      headway_vehicle = headway_vehicle_for(route, direction, calendar_ids: calendar_ids)
      headway_vehicle ? [ headway_vehicle ].first(MAX_VEHICLES_PER_ROUTE_DIRECTION) : []
    end

    # Uses real timetable stop sequences to interpolate vehicle progress along the line.
    def multi_stop_vehicles_for(route, direction, calendar_ids:)
      at_time = time_of_day(@at)
      start_time, end_time = time_window_around(@at, minutes: DEFAULT_WINDOW_MINUTES)

      candidates = ScheduleTrip.joins(:trip_stop_times)
        .where(transit_route_id: route.id, direction: direction, service_calendar_id: calendar_ids)
        .where(pass_time_between_sql(start_time, end_time), start_time: start_time, end_time: end_time)
        .distinct
        .limit(MAX_CANDIDATE_TRIPS)
        .pluck(:id)

      return [] if candidates.empty?

      trips = ScheduleTrip.where(id: candidates).includes(:trip_stop_times)
      vehicles = []

      trips.each do |trip|
        stop_times = trip.ordered_stop_times.to_a
        next unless stop_times.length >= 2

        delay_seconds = Transit::SyntheticDelay.delay_seconds_for_trip(trip, at: @at)
        status = Transit::SyntheticDelay.status_for(delay_seconds)
        effective_at_minutes = minutes_since_midnight(@at) - (delay_seconds / 60.0)

        segment = find_segment_for_time(stop_times, effective_at_minutes)
        next unless segment

        from_stop, to_stop, segment_progress = segment

        vehicles << {
          id: "trip:#{trip.id}",
          train_number: trip.train_number,
          route_id: route.route_id,
          system_id: route.system_id,
          color: route.color,
          from_station_ref: from_stop.station_ref,
          to_station_ref: to_stop.station_ref,
          progress: segment_progress.round(4),
          delay_seconds: delay_seconds,
          status: status,
          destination_name: trip.destination_name
        }

        break if vehicles.length >= MAX_VEHICLES_PER_ROUTE_DIRECTION
      end

      vehicles
    end

    def headway_vehicle_for(route, direction, calendar_ids:)
      station_records = ordered_route_stations(route, direction)
      return nil if station_records.length < 2

      headway_rules = HeadwayRule.where(
        transit_route_id: route.id,
        direction: direction,
        service_calendar_id: calendar_ids
      ).order(:starts_at)

      return nil if headway_rules.empty?

      at_minutes = minutes_since_midnight(@at)
      rule = headway_rule_containing_time(headway_rules, at_minutes) || headway_rules.first

      delay_seconds = Transit::SyntheticDelay.delay_seconds_for_headway(route_id: route.route_id, direction: direction, at: @at)
      status = Transit::SyntheticDelay.status_for(delay_seconds)
      effective_at_minutes = at_minutes - (delay_seconds / 60.0)

      travel_minutes = (station_records.length - 1) * HEADWAY_TRAVEL_MIN_PER_SEGMENT
      return nil if travel_minutes <= 0

      # Simplified looping motion when we don't have full per-stop travel times.
      rule_departure_minutes = minutes_since_midnight(rule.first_departure || rule.starts_at)
      elapsed = modulo_minutes(effective_at_minutes - rule_departure_minutes, travel_minutes)
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

      {
        id: "headway:#{route.id}:#{direction}:#{rule.id}:#{@at.to_i / 3600}",
        train_number: "#{route.route_id}-SIM-#{direction}",
        route_id: route.route_id,
        system_id: route.system_id,
        color: route.color,
        from_station_ref: from_station.station_ref,
        to_station_ref: to_station.station_ref,
        progress: segment_progress.round(4),
        delay_seconds: delay_seconds,
        status: status,
        destination_name: to_station.name
      }
    end

    def headway_rule_containing_time(headway_rules, at_minutes)
      headway_rules.find do |rule|
        start_min = minutes_since_midnight(rule.starts_at)
        end_min = minutes_since_midnight(rule.ends_at)

        if start_min <= end_min
          at_minutes >= start_min && at_minutes <= end_min
        else
          # wraps over midnight
          at_minutes >= start_min || at_minutes <= end_min
        end
      end
    end

    def ordered_route_stations(route, direction)
      # Prefer stations matching the trip direction; fall back to "both".
      preferred = route.transit_route_stations.for_direction(direction).ordered.to_a
      return preferred unless preferred.empty?

      both = route.transit_route_stations.for_direction("both").ordered.to_a
      return both.reverse if direction.to_s == "inbound" || direction.to_s == "reverse"

      both
    end

    # For cyclic daily timetable times, find which adjacent stop pair should contain the effective time.
    # Returns: [from_stop, to_stop, segment_progress_in_0_1]
    def find_segment_for_time(stop_times, effective_at_minutes)
      minutes = normalize_to_0_1440(effective_at_minutes)
      n = stop_times.length

      (0...(n - 1)).each do |i|
        a = minutes_since_midnight(stop_times[i].pass_time)
        b = minutes_since_midnight(stop_times[i + 1].pass_time)

        if within_segment_minutes?(minutes, a, b)
          segment_progress = segment_progress_minutes(minutes, a, b)
          return [ stop_times[i], stop_times[i + 1], segment_progress ]
        end
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

    def ordered_route_stations_indexed(route, direction)
      route.transit_route_stations.for_direction(direction).ordered.to_a
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

    def time_of_day(time)
      t = time.in_time_zone(CLOCK_ZONE)
      Time.utc(2000, 1, 1, t.hour, t.min, t.sec)
    end
  end
end
