# frozen_string_literal: true

module Transit
  class ScheduleImporter
    Result = Data.define(:dataset, :trips, :headways, :skipped)

    def self.import!(client: TdxClient.new, systems: %w[tra hsr metro])
      new(client: client, systems: systems).import!
    end

    def initialize(client:, systems:)
      @client = client
      @systems = systems.map(&:to_s)
      @station_resolver = StationRefResolver.new
      @route_resolver = RouteResolver.new
      @stats = { trips: 0, headways: 0, skipped: 0 }
    end

    def import!
      raise TdxClient::ConfigurationError, "Set TDX_CLIENT_ID and TDX_CLIENT_SECRET to import schedules" unless @client.configured?

      Transit::CatalogSync.sync!

      dataset = ScheduleDataset.create!(
        name: "TDX 時刻表 #{Time.zone.today}",
        source: "tdx",
        valid_from: Time.zone.today,
        notes: "由 TDX API 匯入的臺鐵、高鐵、捷運班次"
      )

      import_tra!(dataset) if @systems.include?("tra")
      import_hsr!(dataset) if @systems.include?("hsr")
      import_metro!(dataset) if @systems.include?("metro")

      dataset.activate!
      Result.new(dataset: dataset, trips: @stats[:trips], headways: @stats[:headways], skipped: @stats[:skipped])
    end

    private

    def import_tra!(dataset)
      timetables = @client.fetch_all("v3/Rail/TRA/GeneralTrainTimetable")

      timetables.each do |entry|
        train_info = entry["TrainInfo"] || entry.dig("GeneralTimetable", "TrainInfo")
        stop_times = entry["StopTimes"] || entry.dig("GeneralTimetable", "StopTimes")
        service_day = entry["ServiceDay"] || entry.dig("GeneralTimetable", "ServiceDay")
        next if train_info.blank? || stop_times.blank?

        import_rail_trip!(
          dataset: dataset,
          system_id: "tra",
          train_info: train_info,
          stop_times: stop_times,
          service_day: service_day,
          train_number_key: "TrainNo",
          direction_key: "Direction",
          trip_type_key: "TrainTypeCode",
          destination_key: "TripHeadSign"
        )
      end
    end

    def import_hsr!(dataset)
      entries = @client.fetch_all("v2/Rail/THSR/GeneralTimetable")
      route = TransitRoute.find_by_manifest!(system_id: "hsr", route_id: "taiwan_hsr")

      entries.each do |wrapper|
        timetable = wrapper["GeneralTimetable"] || wrapper
        train_info = timetable["GeneralTrainInfo"] || timetable["TrainInfo"]
        stop_times = timetable["StopTimes"]
        service_day = timetable["ServiceDay"]
        next if train_info.blank? || stop_times.blank?

        import_rail_trip!(
          dataset: dataset,
          system_id: "hsr",
          route: route,
          train_info: train_info,
          stop_times: stop_times,
          service_day: service_day,
          train_number_key: "TrainNo",
          direction_key: "Direction",
          trip_type_key: "TrainType",
          destination_key: "TripHeadSign"
        )
      end
    end

    def import_metro!(dataset)
      MetroSystemRegistry.entries.each do |entry|
        # Some RailSystem values are not accepted by the Frequency endpoint.
        # We still want to import station timetables for those systems.
        begin
          import_metro_frequency!(dataset, entry)
        rescue TdxClient::RequestError
          @stats[:skipped] += 1
        end

        begin
          import_metro_station_timetables!(dataset, entry)
        rescue TdxClient::RequestError
          @stats[:skipped] += 1
        end
      end
    end

    def import_metro_frequency!(dataset, entry)
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
      timetables = @client.fetch_all("v2/Rail/Metro/StationTimeTable/#{entry.tdx_rail_system}")

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

        Array(record["Timetables"]).each do |slot|
            departure = parse_time(slot["DepartureTime"])
            next unless departure

            train_number = slot["TrainNo"].presence
            trip_key = train_number || "#{origin_ref}-#{destination_name}-#{departure.strftime('%H:%M')}"

            trip = ScheduleTrip.find_or_create_by!(
              schedule_dataset: dataset,
              transit_route: route,
              service_calendar: calendar,
              direction: direction,
              train_number: trip_key
            ) do |trip_record|
              trip_record.destination_name = destination_name
              trip_record.trip_type = metro_trip_type(slot["TrainType"])
              trip_record.notes = "TDX #{entry.tdx_rail_system} 站別時刻"
            end

            next if trip.trip_stop_times.exists?

            TripStopTime.create!(
              schedule_trip: trip,
              station_ref: origin_ref,
              stop_sequence: 1,
              departure_time: departure,
              arrival_time: parse_time(slot["ArrivalTime"]) || departure
            )
            @stats[:trips] += 1
          end
      end
    end

    def import_rail_trip!(dataset:, system_id:, train_info:, stop_times:, service_day:, train_number_key:, direction_key:, trip_type_key:, destination_key:, route: nil)
      train_number = train_info[train_number_key].to_s.presence
      return @stats[:skipped] += 1 if train_number.blank?

      mapped_stops = map_stop_times(system_id: system_id, stop_times: stop_times)
      return @stats[:skipped] += 1 if mapped_stops.length < 2

      route ||= @route_resolver.resolve(system_id: system_id, station_refs: mapped_stops.map { |stop| stop[:station_ref] })
      return @stats[:skipped] += 1 unless route

      direction = rail_direction(train_info[direction_key])
      destination_name = train_info[destination_key].presence || mapped_stops.last[:station_name]
      trip_type = train_info[trip_type_key].to_s.presence

      calendar = ensure_calendar!(dataset, service_day)

      trip = ScheduleTrip.find_or_create_by!(
        schedule_dataset: dataset,
        transit_route: route,
        service_calendar: calendar,
        direction: direction,
        train_number: train_number
      ) do |trip_record|
        trip_record.destination_name = destination_name
        trip_record.trip_type = trip_type
        trip_record.notes = "TDX #{system_id.upcase} 定期時刻"
      end

      return if trip.trip_stop_times.exists?

      mapped_stops.each_with_index do |stop, index|
        TripStopTime.create!(
          schedule_trip: trip,
          station_ref: stop[:station_ref],
          stop_sequence: index + 1,
          arrival_time: stop[:arrival_time],
          departure_time: stop[:departure_time]
        )
      end
      @stats[:trips] += 1
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

    def metro_route(entry, line_id)
      route_id = MetroSystemRegistry.route_id_for(tdx_rail_system: entry.tdx_rail_system, line_id: line_id)
      return nil if route_id.blank?

      TransitRoute.find_by(system_id: entry.system_id, route_id: route_id)
    end

    def rail_direction(value)
      case value.to_i
      when 0 then "forward"
      when 1 then "reverse"
      else "forward"
      end
    end

    def metro_direction(value)
      case value.to_i
      when 0 then "outbound"
      when 1 then "inbound"
      else "forward"
      end
    end

    def metro_trip_type(value)
      case value.to_i
      when 2 then "express"
      when 1 then "local"
      else "local"
      end
    end

    def parse_time(value)
      return nil if value.blank?

      parts = value.to_s.split(":")
      hour = parts[0].to_i
      minute = parts[1].to_i
      second = parts.fetch(2, 0).to_i
      Time.zone.local(2000, 1, 1, hour % 24, minute, second)
    end
  end
end
