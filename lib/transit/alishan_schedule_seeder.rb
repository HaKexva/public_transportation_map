# frozen_string_literal: true

module Transit
  # Seeds Alishan Forest Railway timetable from published mainline / branch services.
  # Source: AFRCH timetable notes applicable from 2025-01-10 (mainline Alishan Express).
  # Zhushan sunrise trains vary daily and are stored as annotated headway rules.
  class AlishanScheduleSeeder
    DATASET_NAME = "阿里山林業鐵路時刻（林鐵處公開班次）"
    SOURCE_NOTE = "依據林鐵處公開本線班次（約自 2025-01-10 起）整理；祝山觀日列車依當日日出公告。"

    # stop_times: [[station_name, "HH:MM"], ...]
    MAINLINE_TRIPS = [
      {
        train_number: "1",
        direction: TransitRoute::DIRECTION_FORWARD,
        trip_type: "express",
        destination_name: "十字路",
        notes: "阿里山號上山；部分班次終點十字路",
        stops: [
          [ "嘉義", "09:00" ],
          [ "北門", "09:06" ],
          [ "竹崎", "09:35" ],
          [ "奮起湖", "11:30" ],
          [ "十字路", "12:00" ]
        ]
      },
      {
        train_number: "5",
        direction: TransitRoute::DIRECTION_FORWARD,
        trip_type: "express",
        destination_name: "阿里山",
        notes: "阿里山號上山；奮起湖停留約 65 分",
        stops: [
          [ "嘉義", "10:00" ],
          [ "北門", "10:06" ],
          [ "竹崎", "10:35" ],
          [ "奮起湖", "12:16" ],
          [ "十字路", "14:20" ],
          [ "阿里山", "14:56" ]
        ]
      },
      {
        train_number: "8",
        direction: TransitRoute::DIRECTION_REVERSE,
        trip_type: "express",
        destination_name: "嘉義",
        notes: "阿里山號下山（阿里山開）",
        stops: [
          [ "阿里山", "11:50" ],
          [ "十字路", "12:20" ],
          [ "奮起湖", "13:10" ],
          [ "竹崎", "14:50" ],
          [ "北門", "15:35" ],
          [ "嘉義", "15:45" ]
        ]
      },
      {
        train_number: "2",
        direction: TransitRoute::DIRECTION_REVERSE,
        trip_type: "express",
        destination_name: "嘉義",
        notes: "阿里山號下山（十字路開）",
        stops: [
          [ "十字路", "13:21" ],
          [ "奮起湖", "14:00" ],
          [ "竹崎", "15:40" ],
          [ "北門", "16:40" ],
          [ "嘉義", "16:51" ]
        ]
      }
    ].freeze

    ZHAOPING_TRIPS = [
      { train_number: "ZP37", depart: "10:30", arrive: "10:36" },
      { train_number: "ZP39", depart: "11:00", arrive: "11:06" },
      { train_number: "ZP41", depart: "11:30", arrive: "11:36" },
      { train_number: "ZP43", depart: "13:00", arrive: "13:06" },
      { train_number: "ZP45", depart: "13:30", arrive: "13:36" },
      { train_number: "ZP47", depart: "14:00", arrive: "14:06" },
      { train_number: "ZP49", depart: "14:30", arrive: "14:36" },
      { train_number: "ZP51", depart: "15:10", arrive: "15:16" }
    ].freeze

    def self.seed!
      new.seed!
    end

    def seed!
      Transit::CatalogSync.sync!

      route = TransitRoute.find_by_manifest!(system_id: "other", route_id: "alishan_forest_railway")
      dataset = ScheduleDataset.find_or_create_by!(name: DATASET_NAME) do |record|
        record.source = "manual"
        record.valid_from = Date.new(2025, 1, 10)
        record.notes = SOURCE_NOTE
      end
      dataset.update!(notes: SOURCE_NOTE, valid_from: Date.new(2025, 1, 10))

      calendar = dataset.service_calendars.find_or_create_by!(code: "daily") do |record|
        record.name = "每日"
      end

      seed_mainline_trips!(dataset, route, calendar)
      seed_zhaoping_trips!(dataset, route, calendar)
      seed_zhushan_headway!(dataset, route, calendar)
      seed_shenmu_headway!(dataset, route, calendar)

      dataset.update!(active: true, imported_at: Time.current)
      dataset
    end

    private

    def seed_mainline_trips!(dataset, route, calendar)
      MAINLINE_TRIPS.each do |spec|
        trip = ScheduleTrip.find_or_initialize_by(
          schedule_dataset: dataset,
          transit_route: route,
          service_calendar: calendar,
          train_number: spec[:train_number],
          direction: spec[:direction]
        )
        trip.trip_type = spec[:trip_type]
        trip.destination_name = spec[:destination_name]
        trip.notes = spec[:notes]
        trip.save!

        trip.trip_stop_times.destroy_all
        spec[:stops].each_with_index do |(station_name, clock), index|
          station = station_by_name(route, station_name)
          next unless station

          pass_time = Time.zone.parse(clock)
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

    def seed_zhaoping_trips!(dataset, route, calendar)
      alishan = station_by_name(route, "阿里山")
      zhaoping = station_by_name(route, "沼平")
      return unless alishan && zhaoping

      ZHAOPING_TRIPS.each do |spec|
        trip = ScheduleTrip.find_or_initialize_by(
          schedule_dataset: dataset,
          transit_route: route,
          service_calendar: calendar,
          train_number: spec[:train_number],
          direction: TransitRoute::DIRECTION_FORWARD
        )
        trip.trip_type = "local"
        trip.destination_name = "沼平"
        trip.notes = "沼平線（園區支線）"
        trip.save!
        trip.trip_stop_times.destroy_all

        depart = Time.zone.parse(spec[:depart])
        arrive = Time.zone.parse(spec[:arrive])
        TripStopTime.create!(
          schedule_trip: trip,
          station_ref: alishan.station_ref,
          stop_sequence: 1,
          arrival_time: depart,
          departure_time: depart
        )
        TripStopTime.create!(
          schedule_trip: trip,
          station_ref: zhaoping.station_ref,
          stop_sequence: 2,
          arrival_time: arrive,
          departure_time: arrive
        )
      end
    end

    def seed_zhushan_headway!(dataset, route, calendar)
      HeadwayRule.find_or_create_by!(
        schedule_dataset: dataset,
        transit_route: route,
        service_calendar: calendar,
        direction: TransitRoute::DIRECTION_FORWARD,
        starts_at: Time.zone.parse("04:00"),
        ends_at: Time.zone.parse("07:30")
      ) do |rule|
        rule.interval_seconds = 30 * 60
        rule.first_departure = Time.zone.parse("04:30")
        rule.last_departure = Time.zone.parse("07:00")
        rule.notes = "祝山觀日列車：發車時刻依日出調整，乘車前一日 16:30 於林鐵官網／阿里山站公告"
      end
    end

    def seed_shenmu_headway!(dataset, route, calendar)
      HeadwayRule.find_or_create_by!(
        schedule_dataset: dataset,
        transit_route: route,
        service_calendar: calendar,
        direction: TransitRoute::DIRECTION_FORWARD,
        starts_at: Time.zone.parse("09:00"),
        ends_at: Time.zone.parse("16:00")
      ) do |rule|
        rule.interval_seconds = 30 * 60
        rule.first_departure = Time.zone.parse("09:00")
        rule.last_departure = Time.zone.parse("15:30")
        rule.notes = "神木線園區支線班距示意（實際班次以林鐵現場／官網為準）"
      end
    end

    def station_by_name(route, name)
      route.transit_route_stations.find { |station| station.name == name }
    end
  end
end
