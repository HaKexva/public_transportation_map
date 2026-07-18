# frozen_string_literal: true

module Transit
  # Seeds published timetables for Taiwan Sugar Railway (糖鐵) routes.
  class SugarRailwayScheduleSeeder
    Result = Data.define(:dataset, :routes, :trips, :headways, :skipped)

    def self.seed!
      new.seed!
    end

    def seed!
      Transit::CatalogSync.sync!

      dataset = ScheduleDataset.find_or_create_by!(name: SugarRailwayScheduleCatalog::DATASET_NAME) do |record|
        record.source = "manual"
        record.valid_from = Date.new(2026, 1, 1)
        record.notes = SugarRailwayScheduleCatalog::SOURCE_NOTE
      end
      dataset.update!(
        notes: SugarRailwayScheduleCatalog::SOURCE_NOTE,
        valid_from: Date.new(2026, 1, 1),
        active: true,
        imported_at: Time.current
      )

      skipped = []
      route_count = 0

      SugarRailwayScheduleCatalog::ROUTES.each do |route_id, spec|
        route = TransitRoute.find_by(system_id: "sugar_railway", route_id: route_id)
        unless route
          skipped << "#{route_id} (route missing)"
          next
        end

        ensure_trip_stations!(route, spec)
        calendars = ensure_calendars!(dataset, spec.fetch(:calendars, { "daily" => "每日" }))
        seed_trips!(dataset, route, calendars, Array(spec[:trips]))
        seed_headways!(dataset, route, calendars, Array(spec[:headways]))
        route_count += 1
      end

      Result.new(
        dataset: dataset,
        routes: route_count,
        trips: dataset.schedule_trips.count,
        headways: dataset.headway_rules.count,
        skipped: skipped
      )
    end

    private

    def ensure_calendars!(dataset, definitions)
      definitions.each_with_object({}) do |(code, name), memo|
        calendar = dataset.service_calendars.find_or_create_by!(code: code) do |record|
          record.name = name
        end
        calendar.update!(name: name) if calendar.name != name
        memo[code] = calendar
      end
    end

    def ensure_trip_stations!(route, spec)
      names = Array(spec[:trips]).flat_map { |trip| Array(trip[:stops]).map(&:first) }.uniq
      return if names.empty?

      existing = route.transit_route_stations.index_by(&:name)
      next_sequence = (route.transit_route_stations.maximum(:stop_sequence) || 0) + 1

      names.each do |name|
        next if existing.key?(name)

        TransitRouteStation.create!(
          transit_route: route,
          station_ref: "#{route.line_ref}#{format('%02d', next_sequence)}",
          name: name,
          stop_sequence: next_sequence,
          direction: TransitRoute::DIRECTION_BOTH
        )
        next_sequence += 1
      end
    end

    def seed_trips!(dataset, route, calendars, trips)
      stations_by_name = route.transit_route_stations.reload.index_by(&:name)

      trips.each do |spec|
        calendar = calendars[spec[:calendar]]
        next unless calendar

        trip = ScheduleTrip.find_or_initialize_by(
          schedule_dataset: dataset,
          transit_route: route,
          service_calendar: calendar,
          train_number: spec[:train_number],
          direction: spec[:direction]
        )
        trip.trip_type = spec[:trip_type] || "local"
        trip.destination_name = spec[:destination_name]
        trip.notes = annotated_notes(spec[:notes], route.route_id)
        trip.save!
        trip.trip_stop_times.destroy_all

        Array(spec[:stops]).each_with_index do |(station_name, clock), index|
          station = stations_by_name[station_name]
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

    def seed_headways!(dataset, route, calendars, headways)
      headways.each do |spec|
        calendar = calendars[spec[:calendar]]
        next unless calendar

        rule = HeadwayRule.find_or_initialize_by(
          schedule_dataset: dataset,
          transit_route: route,
          service_calendar: calendar,
          direction: spec[:direction],
          starts_at: Time.zone.parse(spec[:starts_at]),
          ends_at: Time.zone.parse(spec[:ends_at])
        )
        rule.interval_seconds = spec.fetch(:interval_minutes) * 60
        rule.first_departure = Time.zone.parse(spec[:first_departure]) if spec[:first_departure]
        rule.last_departure = Time.zone.parse(spec[:last_departure]) if spec[:last_departure]
        rule.notes = annotated_notes(spec[:notes], route.route_id)
        rule.save!
      end
    end

    def annotated_notes(notes, route_id)
      source = SugarRailwayScheduleCatalog::ROUTES.dig(route_id, :source)
      [ notes, (source.present? ? "來源：#{source}" : nil) ].compact.join("｜")
    end
  end
end
