# frozen_string_literal: true

module Transit
  class ScheduleSnapshot
    CLOCK_ZONE = ActiveSupport::TimeZone["Taipei"]
    MAX_TRIPS_PER_ROUTE = 800

    def initialize(date:, route_ids:, datasets: ScheduleDataset.active.to_a)
      @date = date.is_a?(Date) ? date : CLOCK_ZONE.parse(date.to_s).to_date
      @route_ids = Array(route_ids).map(&:to_s).reject(&:blank?).uniq
      @datasets = Array(datasets)
    end

    def call
      return { date: @date.iso8601, routes: [] } if @route_ids.empty? || @datasets.blank?

      calendar_ids = ServiceCalendarResolver.calendar_ids_for_date(@date, datasets: @datasets)
      return { date: @date.iso8601, routes: [] } if calendar_ids.empty?

      densifier = ScheduleDensifier.new
      routes = TransitRoute.where(route_id: @route_ids).to_a

      {
        date: @date.iso8601,
        routes: routes.filter_map { |route| serialize_route(route, calendar_ids, densifier) }
      }
    end

    private

    def serialize_route(route, calendar_ids, densifier)
      trips = ScheduleTrip.where(transit_route_id: route.id, service_calendar_id: calendar_ids)
        .limit(MAX_TRIPS_PER_ROUTE)
        .pluck(:id, :train_number, :destination_name, :direction, :trip_type, :notes)

      return serialize_headway_route(route, calendar_ids) if trips.empty?

      trip_ids = trips.map(&:first)
      meta = {}
      trips.each do |id, train_number, destination, direction, trip_type, notes|
        meta[id] = {
          train_number: train_number,
          destination_name: destination,
          direction: direction,
          trip_type: trip_type,
          notes: notes
        }
      end

      stop_rows = TripStopTime.where(schedule_trip_id: trip_ids).pluck(
        :schedule_trip_id, :stop_sequence, :station_ref, :arrival_time, :departure_time
      )
      stops_by_trip = Hash.new { |hash, key| hash[key] = [] }
      stop_rows.each do |trip_id, sequence, ref, arrival, departure|
        stops_by_trip[trip_id] << {
          sequence: sequence,
          station_ref: ref,
          arrival: minutes_since_midnight(arrival || departure),
          departure: minutes_since_midnight(departure || arrival)
        }
      end
      stops_by_trip.each_value { |list| list.sort_by! { |row| row[:sequence] } }

      serialized_trips = trip_ids.filter_map do |trip_id|
        ordered = stops_by_trip[trip_id]
        next if ordered.nil? || ordered.length < 2

        info = meta[trip_id]
        path = densifier.densify(route, ordered).map { |stop| compact_stop(route, stop) }
        next if path.length < 2

        attach_chainage!(route, path)

        continuation = continuation_for(route, calendar_ids)&.lookup(
          trip_id: trip_id,
          train_number: info[:train_number],
          last_station_ref: ordered.last[:station_ref],
          arrival_minutes: ordered.last[:arrival],
          notes: info[:notes]
        )

        {
          id: "trip:#{trip_id}",
          train_number: info[:train_number].to_s,
          destination_name: info[:destination_name],
          direction: info[:direction],
          trip_type: info[:trip_type],
          continues_as: continuation,
          path: path
        }
      end

      return nil if serialized_trips.empty?

      {
        route_id: route.route_id,
        system_id: route.system_id,
        color: route.color,
        name: route.name,
        trips: serialized_trips
      }
    end

    # Headway-only routes (e.g. 文湖線, gondolas) have no stop times; expand each
    # rule window into evenly spaced departures so the client can scrub locally
    # instead of polling /api/vehicles for estimated positions.
    def serialize_headway_route(route, calendar_ids)
      rules = HeadwayRule.where(transit_route_id: route.id, service_calendar_id: calendar_ids)
        .order(:starts_at).to_a
      return nil if rules.empty?

      query = VehiclePositionQuery.new(at: CLOCK_ZONE.now, route_ids: [], datasets: @datasets)
      directions = rules.map(&:direction).compact.uniq
      directions |= directions.filter_map { |direction| query.opposite_direction(direction) }

      budget = MAX_TRIPS_PER_ROUTE
      trips = directions.flat_map do |direction|
        stations = query.ordered_route_stations(route, direction)
        next [] if stations.length < 2

        direction_rules = rules.select { |rule| rule.direction == direction }
        direction_rules = rules.select { |rule| rule.direction == query.opposite_direction(direction) } if direction_rules.empty?

        expanded = headway_trips(route, direction, stations, direction_rules, budget)
        budget -= expanded.length
        expanded
      end
      return nil if trips.empty?

      {
        route_id: route.route_id,
        system_id: route.system_id,
        color: route.color,
        name: route.name,
        trips: trips
      }
    end

    def headway_trips(route, direction, stations, rules, budget)
      segment_minutes = VehiclePositionQuery::HEADWAY_TRAVEL_MIN_PER_SEGMENT
      destination = stations.last.name
      departures = rules.flat_map { |rule| headway_departures(rule) }.uniq.sort

      departures.first([ budget, 0 ].max).map do |departure|
        path = stations.each_with_index.map do |station, index|
          at = (departure + index * segment_minutes) % 1440
          payload = { r: station.station_ref, a: at.round(3), d: at.round(3) }
          payload[:n] = station.name if station.name.present?
          payload
        end
        attach_chainage!(route, path)

        {
          id: "headway:#{route.route_id}:#{direction}:#{departure.round(2)}",
          train_number: "",
          destination_name: destination,
          direction: direction,
          trip_type: nil,
          position_source: "headway_estimate",
          path: path
        }
      end
    end

    def headway_departures(rule)
      window_start = minutes_since_midnight(rule.starts_at)
      window_end = minutes_since_midnight(rule.ends_at)
      window_end += 1440 if window_end <= window_start

      start = rule.first_departure ? minutes_since_midnight(rule.first_departure) : window_start
      start += 1440 if start < window_start
      start = window_start if start > window_end
      finish = window_end
      if rule.last_departure
        last = minutes_since_midnight(rule.last_departure)
        last += 1440 if last < window_start
        finish = [ finish, last + 0.001 ].min
      end

      interval = [ rule.interval_seconds.to_f / 60.0, 2.0 ].max
      departures = []
      at = start
      while at < finish
        departures << (at % 1440).round(3)
        at += interval
      end
      departures
    end

    def continuation_for(route, calendar_ids)
      return nil unless TrainContinuation.relevant_system?(route.system_id)

      @continuation ||= TrainContinuation.new(calendar_ids: calendar_ids)
    end

    def compact_stop(route, stop)
      name = stop[:name].presence || GeojsonStationCoords.lookup_name(route, stop[:station_ref])
      payload = {
        r: stop[:station_ref],
        a: stop[:arrival].to_f.round(3),
        d: stop[:departure].to_f.round(3)
      }
      payload[:n] = name if name.present? && !name.include?(";")
      payload[:t] = true if stop[:through]
      payload
    end

    def attach_chainage!(route, path)
      chainage = TrackChainage.for_route(route)
      return path unless chainage

      @station_km ||= {}
      path.each do |stop|
        key = [ route.id, stop[:r] ]
        unless @station_km.key?(key)
          coord = GeojsonStationCoords.lookup(route, stop[:r])
          km = coord && TrackChainage.nearest_distance(chainage, coord[1], coord[0])
          @station_km[key] = km&.round(4)
        end
        stop[:km] = @station_km[key] if @station_km[key]
      end
      path
    end

    def minutes_since_midnight(time_or_nil)
      return 0 unless time_or_nil

      # Importers write Taipei wall-clock through Time.zone, so `time` columns hold
      # UTC clock values; always read them back in Taipei.
      t = time_or_nil.respond_to?(:in_time_zone) ? time_or_nil.in_time_zone(CLOCK_ZONE) : time_or_nil
      t.hour * 60 + t.min + (t.sec / 60.0)
    end
  end
end
