# frozen_string_literal: true

module Transit
  class StationBoardQuery
    CLOCK_ZONE = ActiveSupport::TimeZone["Taipei"]
    WINDOW_MINUTES = 180
    MAX_ROWS = 32
    PERIOD_MAX_ROWS = 100
    ALL_DAY_MAX_ROWS = 160
    SERVICE_DAY_ROLLOVER_HOUR = 3
    # Express geometry is a separate map layer, but TDX trips are stored on airport_mrt.
    ROUTE_ALIASES = {
      "airport_mrt_express" => %w[airport_mrt],
      "airport_mrt" => %w[airport_mrt]
    }.freeze

    def self.expand_route_ids(route_ids)
      Array(route_ids).flat_map { |id|
        key = id.to_s
        ROUTE_ALIASES.fetch(key, [ key ])
      }.map(&:to_s).reject(&:blank?).uniq
    end

    def initialize(at:, station_ref:, route_ids: nil, datasets: ScheduleDataset.active.to_a, from_minutes: nil, until_minutes: nil)
      @at = at.in_time_zone(CLOCK_ZONE)
      @station_ref = station_ref.to_s
      @route_ids = self.class.expand_route_ids(route_ids)
      @datasets = Array(datasets)
      @from_minutes = normalize_bound(from_minutes)
      @until_minutes = normalize_bound(until_minutes)
      @from_minutes = nil if @from_minutes && @until_minutes.nil?
      @until_minutes = nil if @until_minutes && @from_minutes.nil?
    end

    def call
      tokens = self.class.ref_tokens(@station_ref)
      return empty_payload if tokens.empty? || @datasets.blank?

      calendar_ids = ServiceCalendarResolver.calendar_ids_for_date(service_date, datasets: @datasets)
      return empty_payload if calendar_ids.empty?

      stops = timetable_stops(tokens, calendar_ids)
      stops.concat(headway_stops(tokens, calendar_ids, covered_route_ids: stops.map { |row| row[:route_id] }.to_set))
      stops.sort_by! { |row| [ row[:sort_minutes], row[:route_id].to_s, row[:train_number].to_s ] }
      stops = stops.first(row_limit)

      {
        at: @at.iso8601,
        station_ref: @station_ref,
        stops: stops
      }
    end

    def self.ref_tokens(ref)
      ref.to_s.split(";").map(&:strip).reject(&:blank?).uniq
    end

    def self.station_ref_overlap(scope, tokens)
      return scope.none if tokens.empty?

      scope.where("string_to_array(station_ref, ';') && ARRAY[?]::text[]", tokens)
    end

    private

    def empty_payload
      { at: @at.iso8601, station_ref: @station_ref, stops: [] }
    end

    def service_date
      return @at.to_date if @at.hour >= SERVICE_DAY_ROLLOVER_HOUR

      @at.to_date - 1
    end

    def at_minutes
      @at_minutes ||= @at.hour * 60 + @at.min + (@at.sec / 60.0)
    end

    def timetable_stops(tokens, calendar_ids)
      dataset_ids = @datasets.filter_map { |item| item.respond_to?(:id) ? item.id : item }
      scope = TripStopTime.joins(schedule_trip: :transit_route)
        .where(schedule_trips: { service_calendar_id: calendar_ids, schedule_dataset_id: dataset_ids })
      scope = self.class.station_ref_overlap(scope, tokens)
      scope = scope.where(transit_routes: { route_id: @route_ids }) if @route_ids.any?

      rows = scope.pluck(
        "schedule_trips.id",
        "schedule_trips.train_number",
        "schedule_trips.destination_name",
        "schedule_trips.direction",
        "schedule_trips.trip_type",
        "transit_routes.route_id",
        "transit_routes.name",
        "transit_routes.system_id",
        "transit_routes.color",
        :arrival_time,
        :departure_time,
        :stop_sequence
      )

      rows.filter_map { |row| serialize_stop(row) }
    end

    def serialize_stop(row)
      trip_id, train_number, destination, direction, trip_type, route_id, route_name, system_id, color, arrival, departure, sequence = row
      arrival_minutes = minutes_since_midnight(arrival)
      departure_minutes = minutes_since_midnight(departure)
      sort_minutes = departure_minutes || arrival_minutes
      return if sort_minutes.nil?
      return unless in_window?(sort_minutes)

      wait = wrap_wait(sort_minutes)
      origin = sequence.to_i <= 1 && arrival_minutes && departure_minutes && (departure_minutes - arrival_minutes).abs < 0.05

      {
        id: "trip:#{trip_id}",
        train_number: display_train_number(train_number, destination),
        destination_name: destination,
        direction: direction,
        trip_type: trip_type,
        route_id: route_id,
        route_name: route_name,
        system_id: system_id,
        color: color,
        arrival: origin ? nil : format_clock(arrival_minutes),
        departure: format_clock(departure_minutes),
        arrival_minutes: arrival_minutes,
        departure_minutes: departure_minutes,
        wait: wait.round(1),
        sort_minutes: sort_key(sort_minutes, wait),
        source: "timetable"
      }
    end

    def headway_stops(tokens, calendar_ids, covered_route_ids:)
      stations = self.class.station_ref_overlap(TransitRouteStation.joins(:transit_route), tokens)
      stations = stations.where(transit_routes: { route_id: @route_ids }) if @route_ids.any?

      routes = TransitRoute.where(id: stations.select(:transit_route_id)).to_a
      routes.filter_map do |route|
        next if covered_route_ids.include?(route.route_id)

        rules = HeadwayRule.where(transit_route_id: route.id, service_calendar_id: calendar_ids).order(:starts_at)
        next if rules.empty?

        by_direction = rules.group_by(&:direction)
        if by_direction.key?("outbound") && !by_direction.key?("inbound")
          by_direction["inbound"] = by_direction["outbound"]
        elsif by_direction.key?("forward") && !by_direction.key?("reverse")
          by_direction["reverse"] = by_direction["forward"]
        end
        by_direction.flat_map do |direction, dir_rules|
          rule = dir_rules.find { |item| headway_covers?(item, at_minutes) } || dir_rules.first
          next [] unless rule

          destination = headway_destination(route, direction)
          interval = [ rule.interval_seconds.to_f / 60.0, 2.0 ].max
          upcoming_headway_times(rule, interval).map do |minutes|
            wait = wrap_wait(minutes)
            {
              id: "headway:#{route.id}:#{direction}:#{minutes.round(2)}",
              train_number: nil,
              destination_name: destination,
              direction: direction,
              trip_type: "local",
              route_id: route.route_id,
              route_name: route.name,
              system_id: route.system_id,
              color: route.color,
              arrival: nil,
              departure: format_clock(minutes),
              arrival_minutes: nil,
              departure_minutes: minutes,
              wait: wait.round(1),
              sort_minutes: sort_key(minutes, wait),
              source: "headway_estimate"
            }
          end
        end
      end.flatten
    end

    def upcoming_headway_times(rule, interval)
      start_min = minutes_since_midnight(rule.first_departure || rule.starts_at)
      end_min = minutes_since_midnight(rule.ends_at)
      return [] unless start_min && end_min && interval.positive?

      times = []
      cursor = start_min
      guard = 0
      while cursor <= end_min + 0.01 && times.length < max_headway_times && guard < 800
        times << cursor if in_window?(cursor)
        cursor += interval
        guard += 1
      end
      times
    end

    def headway_covers?(rule, minutes)
      start_min = minutes_since_midnight(rule.starts_at)
      end_min = minutes_since_midnight(rule.ends_at)
      return false unless start_min && end_min

      if start_min <= end_min
        minutes >= start_min && minutes <= end_min
      else
        minutes >= start_min || minutes <= end_min
      end
    end

    def headway_destination(route, direction)
      stations = route.transit_route_stations.order(:stop_sequence).to_a
      return route.name if stations.empty?

      inbound = direction.to_s == "inbound" || direction.to_s == "reverse"
      (inbound ? stations.first : stations.last)&.name
    end

    def display_train_number(train_number, destination)
      value = train_number.to_s.strip
      return nil if value.blank?
      return nil if destination.present? && value.include?(destination) && value.match?(/-\d{1,2}:\d{2}$/)

      value
    end

    def wrap_wait(minutes)
      wait = minutes - at_minutes
      wait += 1440 if wait < -120
      wait
    end

    def in_window?(sort_minutes)
      minutes = wrapped_minutes(sort_minutes)
      if period_filter?
        if @from_minutes <= @until_minutes
          minutes >= @from_minutes && minutes < @until_minutes
        else
          minutes >= @from_minutes || minutes < @until_minutes
        end
      else
        wait = wrap_wait(sort_minutes)
        wait >= -0.5 && wait <= WINDOW_MINUTES
      end
    end

    def period_filter?
      !@from_minutes.nil? && !@until_minutes.nil?
    end

    def sort_key(sort_minutes, wait)
      return wrapped_minutes(sort_minutes) if period_filter?

      sort_minutes + (wait >= 0 ? 0 : 1440)
    end

    def wrapped_minutes(minutes)
      ((minutes % 1440) + 1440) % 1440
    end

    def row_limit
      return ALL_DAY_MAX_ROWS if period_filter? && period_span >= 720
      return PERIOD_MAX_ROWS if period_filter?

      MAX_ROWS
    end

    def period_span
      span = @until_minutes.to_i - @from_minutes.to_i
      span += 1440 if span <= 0
      span
    end

    def max_headway_times
      period_filter? ? 24 : 12
    end

    def normalize_bound(value)
      return nil if value.nil? || value == ""

      Integer(value).clamp(0, 1440)
    rescue ArgumentError, TypeError
      nil
    end

    def format_clock(minutes)
      return nil unless minutes

      wrapped = ((minutes % 1440) + 1440) % 1440
      hour = wrapped.floor / 60
      minute = (wrapped % 60).floor
      format("%02d:%02d", hour, minute)
    end

    def minutes_since_midnight(time_or_nil)
      return nil unless time_or_nil

      if time_or_nil.is_a?(ActiveSupport::TimeWithZone)
        t = time_or_nil.in_time_zone(CLOCK_ZONE)
        return t.hour * 60 + t.min + (t.sec / 60.0)
      end

      t = time_or_nil.respond_to?(:utc) ? time_or_nil.utc : time_or_nil
      t.hour * 60 + t.min + (t.sec / 60.0)
    end
  end
end
