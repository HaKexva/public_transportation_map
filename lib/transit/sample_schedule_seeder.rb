# frozen_string_literal: true

module Transit
  class SampleScheduleSeeder
    def self.seed!
      new.seed!
    end

    def seed!
      route = TransitRoute.find_by_manifest!(system_id: "taipei_metro", route_id: "bannan")
      dataset = ScheduleDataset.find_or_create_by!(name: "範例：板南線平日時刻") do |record|
        record.source = "manual"
        record.valid_from = Date.current
        record.notes = "示範固定班次與班距規則的種子資料"
      end

      calendar = dataset.service_calendars.find_or_create_by!(code: "weekday") do |record|
        record.name = ServiceCalendar::COMMON_CODES.fetch("weekday")
      end

      seed_headway_rule!(dataset, route, calendar)
      seed_sample_trip!(dataset, route, calendar)
      dataset.activate!
    end

    private

    def seed_headway_rule!(dataset, route, calendar)
      HeadwayRule.find_or_create_by!(
        schedule_dataset: dataset,
        transit_route: route,
        service_calendar: calendar,
        direction: "forward",
        starts_at: Time.zone.parse("07:00"),
        ends_at: Time.zone.parse("09:00")
      ) do |rule|
        rule.interval_seconds = 3 * 60
        rule.first_departure = Time.zone.parse("06:02")
        rule.last_departure = Time.zone.parse("00:02")
        rule.notes = "早高峰班距示意"
      end
    end

    def seed_sample_trip!(dataset, route, calendar)
      stations = route.transit_route_stations.ordered.to_a
      return if stations.length < 2

      trip = ScheduleTrip.find_or_create_by!(
        schedule_dataset: dataset,
        transit_route: route,
        service_calendar: calendar,
        direction: "forward",
        train_number: "BL-DEMO-1"
      ) do |record|
        record.trip_type = "local"
        record.destination_name = stations.last.name
        record.notes = "首班示意車次"
      end

      return if trip.trip_stop_times.exists?

      start_time = Time.zone.parse("06:02")
      stations.each_with_index do |station, index|
        pass_time = start_time + (index * 2).minutes
        TripStopTime.create!(
          schedule_trip: trip,
          station_ref: station.station_ref,
          stop_sequence: index + 1,
          arrival_time: pass_time,
          departure_time: pass_time
        )
      end
    end
  end
end
