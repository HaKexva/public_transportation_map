# frozen_string_literal: true

module Transit
  class ScheduleSnapshot
    CLOCK_ZONE = ActiveSupport::TimeZone["Taipei"]
    MAX_TRIPS_PER_ROUTE = 800

    def initialize(date:, route_ids:)
      @date = date.is_a?(Date) ? date : CLOCK_ZONE.parse(date.to_s).to_date
      @route_ids = Array(route_ids).map(&:to_s).reject(&:blank?).uniq
    end

    def call
      return { date: @date.iso8601, routes: [] } if @route_ids.empty?

      calendar_ids = ServiceCalendarResolver.calendar_ids_for_date(@date)
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

      return nil if trips.empty?

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

        continuation = TrainContinuation.new(calendar_ids: calendar_ids).lookup(
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

      path.each do |stop|
        coord = GeojsonStationCoords.lookup(route, stop[:r])
        next unless coord

        km = TrackChainage.nearest_distance(chainage, coord[1], coord[0])
        stop[:km] = km.round(4) if km
      end
      path
    end

    def minutes_since_midnight(time_or_nil)
      return 0 unless time_or_nil

      if time_or_nil.is_a?(ActiveSupport::TimeWithZone) && time_or_nil.year != 2000
        t = time_or_nil.in_time_zone(CLOCK_ZONE)
        return t.hour * 60 + t.min + (t.sec / 60.0)
      end

      t = time_or_nil.respond_to?(:utc) ? time_or_nil.utc : time_or_nil
      t.hour * 60 + t.min + (t.sec / 60.0)
    end
  end
end
