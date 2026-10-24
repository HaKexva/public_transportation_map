# frozen_string_literal: true

module Transit
  class ScheduleImporter
    Result = Data.define(:dataset, :trips, :headways, :skipped)
    STOP_TIME_BATCH = 1_000
    OVERLAY_DESCRIPTIONS = %w[連假 颱風假].freeze

    def self.import!(client: TdxClient.new(ignore_breaker: true), systems: %w[tra hsr metro], dataset: nil, ods_client: nil)
      new(client: client, systems: systems, ods_client: ods_client).import!(dataset: dataset)
    end

    # Writes only the given dates onto an existing dataset. Used for a 連假,
    # so the weekly timetable on the surrounding days stays as it is.
    def self.import_dates!(dataset:, dates:, description: "連假", client: TdxClient.new(ignore_breaker: true), systems: %w[tra hsr], ods_client: nil)
      new(client: client, systems: systems, ods_client: ods_client).import_dates!(dataset:, dates:, description:)
    end

    def initialize(client:, systems:, ods_client: nil)
      @client = client
      @systems = systems.map(&:to_s)
      @ods_client = ods_client || TraOdsClient.new
      @station_resolver = StationRefResolver.new
      @route_resolver = RouteResolver.new
      @metro_stitcher = MetroTripStitcher.new
      @stats = { trips: 0, headways: 0, skipped: 0 }
      @pending_stop_times = []
    end

    def import!(dataset: nil)
      needs_tdx = (@systems & %w[hsr metro]).any?
      if needs_tdx
        unless @client.configured?
          raise TdxClient::ConfigurationError, "Set TDX_CLIENT_ID and TDX_CLIENT_SECRET to import HSR/metro schedules"
        end

        @client.probe! if @client.respond_to?(:probe!)
      end

      CatalogSync.sync!

      created_dataset = dataset.nil?
      dataset ||= ScheduleDataset.create!(
        name: "時刻表 #{Time.zone.today}",
        source: "tdx",
        valid_from: Time.zone.today,
        notes: "臺鐵來自 ODS 每日時刻；高鐵／捷運來自 TDX"
      )

      begin
        import_tra!(dataset) if @systems.include?("tra")
        import_hsr!(dataset) if @systems.include?("hsr")
        import_metro!(dataset) if @systems.include?("metro")
        flush_stop_times!

        if @stats[:trips].zero? && @stats[:headways].zero? && dataset.schedule_trips.none? && dataset.headway_rules.none?
          raise TdxClient::RequestError, "Schedule import produced no trips or headways"
        end

        dataset.activate!
        ScheduleDataset.discard_replaced!(source: "tdx", keep_id: dataset.id)
        deactivate_demo_metro_dataset!
      rescue TdxClient::Error, TraOdsClient::Error, ActiveRecord::ActiveRecordError, JSON::ParserError
        ScheduleDataset.delete_dataset!(dataset) if created_dataset && dataset.persisted? && !dataset.active?
        raise
      end

      Result.new(dataset: dataset, trips: @stats[:trips], headways: @stats[:headways], skipped: @stats[:skipped])
    end

    def import_dates!(dataset:, dates:, description: "連假")
      raise ArgumentError, "date import needs an existing dataset" unless dataset&.persisted?

      @date_description = description

      dates = Array(dates).map(&:to_date).uniq.sort
      return Result.new(dataset:, trips: 0, headways: 0, skipped: 0) if dates.empty?

      if @systems.include?("hsr")
        unless @client.configured?
          raise TdxClient::ConfigurationError, "Set TDX_CLIENT_ID and TDX_CLIENT_SECRET to import HSR schedules"
        end

        @client.probe! if @client.respond_to?(:probe!)
      end

      import_tra_dates!(dataset, dates) if @systems.include?("tra")
      import_hsr!(dataset, dates:, holiday: true) if @systems.include?("hsr")
      flush_stop_times!
      log_progress("holiday dates #{dates.map(&:iso8601).join(', ')}: #{@stats[:trips]} trips")
      Result.new(dataset:, trips: @stats[:trips], headways: @stats[:headways], skipped: @stats[:skipped])
    end

    private

    def deactivate_demo_metro_dataset!
      ScheduleDataset.where(name: SampleScheduleSeeder::DATASET_NAME).update_all(active: false)
    end

    def import_tra!(dataset)
      log_progress("TRA ODS daily timetable")
      each_ods_day { |day| import_tra_day!(dataset, day) }
    end

    def import_tra_dates!(dataset, dates)
      log_progress("TRA ODS holiday dates #{dates.map(&:iso8601).join(', ')}")
      each_ods_day(dates:) { |day| import_tra_day!(dataset, day, description: @date_description) }
    end

    def import_tra_day!(dataset, day, description: "單日營運日曆")
      with_date_transaction do
        calendar = ensure_date_calendar!(dataset, day[:date], description:)
        replace_calendar_trips!(calendar) if OVERLAY_DESCRIPTIONS.include?(description)
        Array(day[:trains]).each do |entry|
          train_info = entry["TrainInfo"] || entry
          stop_times = entry["StopTimes"]
          next if train_info.blank? || stop_times.blank?

          import_rail_trip!(
            dataset: dataset,
            system_id: "tra",
            train_info: train_info,
            stop_times: stop_times,
            calendar: calendar,
            train_number_key: "TrainNo",
            direction_key: "Direction",
            trip_type_key: "TrainTypeCode",
            destination_key: "TripHeadSign",
            notes_prefix: "ODS TRA"
          )
        end
        flush_stop_times!
      end
    end

    def import_hsr!(dataset, dates: nil, holiday: false)
      dates ||= (0..6).map { |offset| Time.zone.today + offset }
      log_progress(holiday ? "THSR #{@date_description} dates #{dates.map(&:iso8601).join(', ')}" : "THSR DailyTimetable")
      route = TransitRoute.find_by_manifest!(system_id: "hsr", route_id: "taiwan_hsr")
      description = holiday ? @date_description : "單日營運日曆"

      dates.each do |date|
        path = date == Time.zone.today ? "v2/Rail/THSR/DailyTimetable/Today" : "v2/Rail/THSR/DailyTimetable/#{date}"
        entries = @client.fetch_all(path)
        with_date_transaction do
          calendar = ensure_date_calendar!(dataset, date, description:)
          replace_calendar_trips!(calendar) if OVERLAY_DESCRIPTIONS.include?(description)
          import_hsr_entries!(dataset, route, calendar, entries)
          flush_stop_times!
        end
      end
    end

    def import_hsr_entries!(dataset, route, calendar, entries)
      entries.each do |wrapper|
          train_info = wrapper["DailyTrainInfo"] || wrapper["TrainInfo"]
          stop_times = wrapper["StopTimes"]
          next if train_info.blank? || stop_times.blank?

          import_rail_trip!(
            dataset: dataset,
            system_id: "hsr",
            route: route,
            train_info: train_info,
            stop_times: stop_times,
            calendar: calendar,
            train_number_key: "TrainNo",
            direction_key: "Direction",
            trip_type_key: "TrainType",
            destination_key: "TripHeadSign",
            notes_prefix: "TDX HSR"
          )
        end
    end

    def import_metro!(dataset)
      MetroSystemRegistry.entries.each do |entry|
        with_metro_skip(entry, "frequency") { import_metro_frequency!(dataset, entry) }
        with_metro_skip(entry, "station timetable") { import_metro_station_timetables!(dataset, entry) }
      end
    end

    def import_metro_frequency!(dataset, entry)
      return if metro_headways_present?(dataset, entry)

      log_progress("metro frequency #{entry.tdx_rail_system}")
      frequencies = @client.fetch_all("v2/Rail/Metro/Frequency/#{entry.tdx_rail_system}")

      frequencies.each do |record|
        route = metro_route(entry, record["LineID"])
        next unless route

        calendar = ensure_calendar!(dataset, record["ServiceDay"])
        direction = metro_direction(record["Direction"])

        Array(record["Headways"]).each do |headway|
          interval_seconds = headway["MinHeadwayMins"].to_i * 60
          next if interval_seconds <= 0

          HeadwayRule.find_or_create_by!(
            schedule_dataset: dataset,
            transit_route: route,
            service_calendar: calendar,
            direction: direction,
            starts_at: parse_time(headway["StartTime"]),
            ends_at: parse_time(headway["EndTime"])
          ) do |rule|
            rule.interval_seconds = interval_seconds
            rule.notes = "TDX #{entry.tdx_rail_system} #{record['LineID']} 班距"
          end
          @stats[:headways] += 1
        end
      end
    end

    def import_metro_station_timetables!(dataset, entry)
      return if metro_trips_present?(dataset, entry)

      log_progress("metro station timetable #{entry.tdx_rail_system}")
      timetables = @client.fetch_all("v2/Rail/Metro/StationTimeTable/#{entry.tdx_rail_system}")
      boards_by_key = Hash.new { |hash, key| hash[key] = [] }

      timetables.each do |record|
        route = metro_route(entry, record["LineID"])
        next unless route

        origin_ref = @station_resolver.resolve_ref(
          system_id: entry.system_id,
          tdx_station_id: record["StationID"],
          line_ref: record["LineID"],
          station_name: ResponseDecoder.localized_name(record["StationName"])
        )
        next if origin_ref.blank?

        destination_name = ResponseDecoder.localized_name(record["DestinationStationName"])
        direction = metro_direction(record["Direction"])
        calendar = ensure_calendar!(dataset, record["ServiceDay"])
        sequence = metro_station_sequence(route, origin_ref)

        Array(record["Timetables"]).each do |slot|
          departure = parse_time(slot["DepartureTime"])
          next unless departure

          boards_by_key[[ route.id, direction, calendar.id ]] << {
            route_id: route.id,
            direction: direction,
            calendar_code: calendar.code,
            train_number: slot["TrainNo"].presence,
            destination_name: destination_name,
            trip_type: metro_trip_type(slot["TrainType"]),
            station_ref: origin_ref,
            sequence: sequence,
            arrival_time: parse_time(slot["ArrivalTime"]) || departure,
            departure_time: departure,
            departure_minutes: minutes_since_midnight(departure)
          }
        end
      end

      boards_by_key.each do |(route_id, direction, calendar_id), boards|
        route = TransitRoute.find(route_id)
        calendar = ServiceCalendar.find(calendar_id)
        trips = @metro_stitcher.stitch(boards)
        if trips.empty?
          persist_single_stop_metro_trips!(dataset, route, calendar, direction, boards)
          next
        end

        trips.each { |trip| persist_stitched_metro_trip!(dataset, route, calendar, direction, trip) }
      end
    end

    def persist_stitched_metro_trip!(dataset, route, calendar, direction, trip)
      record = ScheduleTrip.find_or_create_by!(
        schedule_dataset: dataset,
        transit_route: route,
        service_calendar: calendar,
        direction: direction,
        train_number: trip.train_number
      ) do |trip_record|
        trip_record.destination_name = trip.destination_name
        trip_record.trip_type = trip.trip_type
        trip_record.notes = "TDX 捷運縫合班次"
      end
      append_stop_times!(record, trip.stops, fresh: record.previously_new_record?)
    end

    def persist_single_stop_metro_trips!(dataset, route, calendar, direction, boards)
      boards.each do |board|
        trip_key = board[:train_number].presence || "#{board[:station_ref]}-#{board[:destination_name]}-#{format_clock(board[:departure_time])}"
        trip = ScheduleTrip.find_or_create_by!(
          schedule_dataset: dataset,
          transit_route: route,
          service_calendar: calendar,
          direction: direction,
          train_number: trip_key
        ) do |trip_record|
          trip_record.destination_name = board[:destination_name]
          trip_record.trip_type = board[:trip_type]
          trip_record.notes = "TDX 捷運站別時刻"
        end
        append_stop_times!(
          trip,
          [ { station_ref: board[:station_ref], arrival_time: board[:arrival_time], departure_time: board[:departure_time] } ],
          fresh: trip.previously_new_record?
        )
      end
    end

    def import_rail_trip!(dataset:, system_id:, train_info:, stop_times:, train_number_key:, direction_key:, trip_type_key:, destination_key:, notes_prefix:, route: nil, calendar: nil, service_day: nil)
      train_number = train_info[train_number_key].to_s.presence
      return @stats[:skipped] += 1 if train_number.blank?

      mapped_stops = map_stop_times(system_id: system_id, stop_times: stop_times)
      return @stats[:skipped] += 1 if mapped_stops.length < 2

      route ||= @route_resolver.resolve(system_id: system_id, station_refs: mapped_stops.map { |stop| stop[:station_ref] })
      return @stats[:skipped] += 1 unless route

      direction = rail_direction(train_info[direction_key])
      destination_name = train_info[destination_key].presence || mapped_stops.last[:station_name]
      trip_type = train_info[trip_type_key].to_s.presence
      calendar ||= ensure_calendar!(dataset, service_day)
      notes = train_info["Note"].to_s.strip.presence || "#{notes_prefix} 時刻"

      trip = ScheduleTrip.find_or_create_by!(
        schedule_dataset: dataset,
        transit_route: route,
        service_calendar: calendar,
        direction: direction,
        train_number: train_number
      ) do |trip_record|
        trip_record.destination_name = destination_name
        trip_record.trip_type = trip_type
        trip_record.notes = notes
      end
      fresh = trip.previously_new_record?
      trip.update!(notes: notes) if trip.notes != notes
      append_stop_times!(trip, mapped_stops, fresh:)
    end

    def append_stop_times!(trip, stops, fresh:)
      return if stops.blank?
      return if !fresh && trip.trip_stop_times.exists?

      now = Time.current
      stops.each_with_index do |stop, index|
        @pending_stop_times << {
          schedule_trip_id: trip.id,
          station_ref: stop[:station_ref],
          stop_sequence: index + 1,
          arrival_time: stop[:arrival_time],
          departure_time: stop[:departure_time],
          created_at: now,
          updated_at: now
        }
      end
      @stats[:trips] += 1
      flush_stop_times! if @pending_stop_times.size >= STOP_TIME_BATCH
    end

    def flush_stop_times!
      return if @pending_stop_times.empty?

      TripStopTime.insert_all(@pending_stop_times)
      @pending_stop_times = []
    end

    def each_ods_day(dates: nil, &block)
      if @ods_client.respond_to?(:each_daily_timetable)
        if dates
          @ods_client.each_daily_timetable(dates:, min_days: 0, &block)
        else
          @ods_client.each_daily_timetable(&block)
        end
      else
        @ods_client.fetch_daily_timetables.each(&block)
      end
    end

    def with_date_transaction
      ScheduleDataset.transaction { yield }
    rescue StandardError
      @pending_stop_times = []
      raise
    end

    def replace_calendar_trips!(calendar)
      trip_ids = ScheduleTrip.where(service_calendar_id: calendar.id).pluck(:id)
      return if trip_ids.empty?

      TripStopTime.where(schedule_trip_id: trip_ids).delete_all
      ScheduleTrip.where(id: trip_ids).delete_all
    end

    def map_stop_times(system_id:, stop_times:)
      stop_times.filter_map do |stop|
        station_name = ResponseDecoder.localized_name(stop["StationName"])
        station_ref = @station_resolver.resolve_ref(
          system_id: system_id,
          tdx_station_id: stop["StationID"],
          station_name: station_name
        )
        next if station_ref.blank?

        {
          station_ref: station_ref,
          station_name: station_name,
          arrival_time: parse_time(stop["ArrivalTime"]),
          departure_time: parse_time(stop["DepartureTime"])
        }
      end
    end

    def ensure_calendar!(dataset, service_day)
      code = "sd_#{ServiceDayMapper.fingerprint(service_day)}"
      dataset.service_calendars.find_or_create_by!(code: code) do |calendar|
        calendar.name = ServiceDayMapper.calendar_name(service_day)
        calendar.description = "TDX 營運日型態"
      end
    end

    def ensure_date_calendar!(dataset, date, description: "單日營運日曆")
      code = "date_#{date.iso8601}"
      calendar = dataset.service_calendars.find_or_create_by!(code: code) do |row|
        row.name = date.strftime("%Y-%m-%d")
        row.description = description
      end
      calendar.update!(description:) if calendar.description != description
      calendar
    end

    def metro_route(entry, line_id)
      route_id = MetroSystemRegistry.route_id_for(tdx_rail_system: entry.tdx_rail_system, line_id: line_id)
      return nil if route_id.blank?

      TransitRoute.find_by(system_id: entry.system_id, route_id: route_id)
    end

    def metro_station_sequence(route, station_ref)
      station = route.transit_route_stations.ordered.find do |row|
        row.station_ref == station_ref || row.station_ref.split(";").include?(station_ref)
      end
      station&.stop_sequence || 0
    end

    def rail_direction(value)
      value.to_i == 1 ? "reverse" : "forward"
    end

    def metro_direction(value)
      value.to_i == 1 ? "inbound" : "outbound"
    end

    def metro_trip_type(value)
      value.to_i == 2 ? "express" : "local"
    end

    def parse_time(value)
      return nil if value.blank?

      parts = value.to_s.split(":")
      hour = parts[0].to_i
      minute = parts[1].to_i
      second = parts.fetch(2, 0).to_i
      Time.zone.local(2000, 1, 1, hour % 24, minute, second)
    end

    def minutes_since_midnight(time)
      time.hour * 60 + time.min + (time.sec / 60.0)
    end

    def format_clock(time)
      time.strftime("%H:%M")
    end

    def with_metro_skip(entry, label)
      yield
    rescue StandardError => e
      log_progress("skip metro #{label} #{entry.tdx_rail_system}: #{e.class}: #{e.message}")
      @stats[:skipped] += 1
    end

    def metro_route_ids(entry)
      entry.line_map.values.map(&:to_s).uniq
    end

    def metro_trips_present?(dataset, entry)
      ScheduleTrip.joins(:transit_route).exists?(
        schedule_dataset_id: dataset.id,
        transit_routes: { route_id: metro_route_ids(entry) }
      )
    end

    def metro_headways_present?(dataset, entry)
      HeadwayRule.joins(:transit_route).exists?(
        schedule_dataset_id: dataset.id,
        transit_routes: { route_id: metro_route_ids(entry) }
      )
    end

    def log_progress(message)
      Rails.logger.info("[ScheduleImporter] #{message}")
      $stdout.puts("[ScheduleImporter] #{message}")
      $stdout.flush
    end
  end
end
