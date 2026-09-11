# frozen_string_literal: true

require "test_helper"

class VehiclePositionQueryTest < ActiveSupport::TestCase
  # These tests depend on schedule data seeded via `rails db:seed` or TDX import.
  # They are skipped when the DB has no schedule data.

  def self.has_schedule_data?
    TransitRoute.where(route_id: "bannan").exists? &&
      ServiceCalendar.exists?
  end

  setup do
    skip "No schedule data in test DB – run rails db:seed first" unless self.class.has_schedule_data?
    @at = Time.new(2026, 7, 27, 10, 0, 0, "+08:00").in_time_zone("Asia/Taipei")
  end

  test "returns empty array when route_ids is empty" do
    result = Transit::VehiclePositionQuery.new(at: @at, route_ids: []).call
    assert_equal [], result
  end

  test "returns empty array when datasets are blank" do
    result = Transit::VehiclePositionQuery.new(at: @at, route_ids: [ "bannan" ], datasets: []).call
    assert_equal [], result
  end

  test "returns empty array for unknown route_id" do
    result = Transit::VehiclePositionQuery.new(at: @at, route_ids: [ "nonexistent_xyz" ]).call
    assert_equal [], result
  end

  test "returns vehicles for bannan route during service hours" do
    result = Transit::VehiclePositionQuery.new(at: @at, route_ids: [ "bannan" ]).call
    assert result.length >= 1, "Expected at least 1 vehicle on bannan at 10:00"

    vehicle = result.first
    assert_equal "on_time", vehicle[:status]
    assert_equal 0, vehicle[:delay_seconds]
    assert_equal "none", vehicle[:delay_source]
    assert_equal "station_timetable", vehicle[:position_source]
    assert vehicle[:destination_name].present?
    assert vehicle[:label].to_s.include?(vehicle[:destination_name].to_s)
    assert_kind_of Numeric, vehicle[:progress]
    assert vehicle[:progress] >= 0 && vehicle[:progress] <= 1
    assert vehicle[:from_station_ref].present?
    assert vehicle[:to_station_ref].present?
    assert vehicle.key?(:departure_minutes)
    assert vehicle.key?(:arrival_minutes)
    assert_equal "bannan", vehicle[:route_id]
    assert_equal "taipei_metro", vehicle[:system_id]
  end

  test "returns vehicles for TRA western_trunk_north" do
    result = Transit::VehiclePositionQuery.new(at: @at, route_ids: [ "western_trunk_north" ]).call
    assert result.length >= 1, "Expected TRA trains at 10:00 weekday"

    vehicle = result.first
    assert_equal "on_time", vehicle[:status]
    assert_equal "timetable", vehicle[:position_source]
    assert vehicle[:train_number].present?
    assert_equal vehicle[:train_number], vehicle[:label]
    assert vehicle[:from_station_name].present?, "TRA vehicles should expose station names"
    assert_no_match(/;/, vehicle[:from_station_name].to_s)
    assert vehicle[:to_station_name].present?
    assert_no_match(/;/, vehicle[:to_station_name].to_s)
    assert_kind_of Array, vehicle[:path]
    assert vehicle[:path].length >= 2, "TRA vehicles need a stop path for local scrubbing"
    assert vehicle[:path].first[:r].present? || vehicle[:path].first["r"].present?
  end

  test "vehicle hash contains required keys" do
    result = Transit::VehiclePositionQuery.new(at: @at, route_ids: [ "bannan" ]).call
    skip "No vehicles returned" if result.empty?

    vehicle = result.first
    %i[id route_id system_id from_station_ref to_station_ref progress delay_seconds status position_source delay_source].each do |key|
      assert vehicle.key?(key), "Missing key #{key}"
    end
  end

  test "returns vehicles from multiple systems in one call" do
    result = Transit::VehiclePositionQuery.new(
      at: @at,
      route_ids: %w[bannan western_trunk_north taiwan_hsr]
    ).call

    route_ids = result.map { |v| v[:route_id] }.uniq
    assert route_ids.length >= 2, "Expected vehicles from at least 2 different routes"
  end

  test "does not artificially cap metro vehicles to a tiny fleet" do
    result = Transit::VehiclePositionQuery.new(at: @at, route_ids: [ "bannan" ]).call
    assert result.length > 20, "Expected a full station-timetable fleet, got #{result.length}"
  end

  test "progress is within 0..1 for all returned vehicles" do
    result = Transit::VehiclePositionQuery.new(at: @at, route_ids: %w[bannan western_trunk_north]).call
    result.each do |v|
      assert v[:progress] >= 0 && v[:progress] <= 1,
             "progress #{v[:progress]} out of bounds for #{v[:id]}"
    end
  end

  test "metro vehicle progress advances with simulation time" do
    earlier = Transit::VehiclePositionQuery.new(at: @at, route_ids: [ "bannan" ]).call
    later_at = @at + 90.seconds
    later = Transit::VehiclePositionQuery.new(at: later_at, route_ids: [ "bannan" ]).call

    skip "Need overlapping vehicles across the window" if earlier.empty? || later.empty?

    # Same segment wave should move forward (or roll into the next segment).
    moved = earlier.any? do |before|
      after = later.find { |v| v[:id] == before[:id] }
      next false unless after

      after[:progress] > before[:progress]
    end || earlier.map { |v| v[:id] }.sort != later.map { |v| v[:id] }.sort

    assert moved, "Expected metro positions/IDs to change after 90 seconds"
  end

  test "orders bannan stations by BL number not broken stop_sequence" do
    route = TransitRoute.find_by!(route_id: "bannan")
    query = Transit::VehiclePositionQuery.new(at: @at, route_ids: [ "bannan" ])
    stations = query.send(:ordered_route_stations, route, "outbound")
    refs = stations.map(&:station_ref)
    bl_numbers = refs.filter_map { |ref| ref[/BL(\d+)/, 1]&.to_i }
    assert_equal bl_numbers.sort, bl_numbers, "BL stations should be ordered by number"
  end

  test "service_date_for uses previous day before rollover hour" do
    query = Transit::VehiclePositionQuery.new(at: @at, route_ids: [ "bannan" ])
    early = Time.new(2026, 7, 28, 0, 30, 0, "+08:00").in_time_zone("Asia/Taipei")
    late = Time.new(2026, 7, 28, 3, 0, 0, "+08:00").in_time_zone("Asia/Taipei")

    assert_equal Date.new(2026, 7, 27), query.send(:service_date_for, early)
    assert_equal Date.new(2026, 7, 28), query.send(:service_date_for, late)
  end

  test "metro overnight hop stays visible just after midnight" do
    at_pre = Time.new(2026, 7, 27, 23, 55, 0, "+08:00").in_time_zone("Asia/Taipei")
    at_post = Time.new(2026, 7, 28, 0, 5, 0, "+08:00").in_time_zone("Asia/Taipei")

    pre = Transit::VehiclePositionQuery.new(at: at_pre, route_ids: [ "bannan" ]).call
    skip "No late-evening bannan vehicles" if pre.empty?

    wrapping_pre = pre.select { |v| v[:motion_departure_minutes].to_f > v[:motion_arrival_minutes].to_f }
    skip "No wrapping hops before midnight" if wrapping_pre.empty?

    post = Transit::VehiclePositionQuery.new(at: at_post, route_ids: [ "bannan" ]).call
    wrapping_post = post.select { |v| v[:motion_departure_minutes].to_f > v[:motion_arrival_minutes].to_f }

    assert wrapping_post.any?,
           "Expected wrapping bannan hops to remain visible at 00:05, got #{post.size} vehicles"
  end

  test "wrapped_minute_span crosses midnight" do
    query = Transit::VehiclePositionQuery.new(at: @at, route_ids: [ "bannan" ])
    assert_in_delta 20, query.send(:wrapped_minute_span, 1430, 10), 0.001
    assert_in_delta 0, query.send(:wrapped_minute_span, 100, 100), 0.001
    assert_in_delta 60, query.send(:wrapped_minute_span, 100, 160), 0.001
  end
end

class VehicleDirectionSelectionTest < ActiveSupport::TestCase
  test "ignores inactive dataset directions so metro keeps outbound/inbound" do
    route = TransitRoute.create!(
      system_id: "taipei_metro",
      route_id: "direction_select_line",
      name: "方向測試線",
      line_ref: "DS",
      color: "#000000",
      geojson_path: "/geojson/does-not-exist.geojson"
    )
    active = ScheduleDataset.create!(name: "active tdx", source: "tdx", active: true)
    stale = ScheduleDataset.create!(name: "stale demo", source: "manual", active: false)
    live_cal = ServiceCalendar.create!(schedule_dataset: active, code: "weekday", name: "平日")
    stale_cal = ServiceCalendar.create!(schedule_dataset: stale, code: "weekday", name: "舊平日")

    ScheduleTrip.create!(
      schedule_dataset: active, transit_route: route, service_calendar: live_cal,
      direction: "outbound", train_number: "A1", destination_name: "終點"
    )
    ScheduleTrip.create!(
      schedule_dataset: active, transit_route: route, service_calendar: live_cal,
      direction: "inbound", train_number: "A2", destination_name: "起點"
    )
    ScheduleTrip.create!(
      schedule_dataset: stale, transit_route: route, service_calendar: stale_cal,
      direction: "forward", train_number: "DEMO", destination_name: "示範"
    )

    query = Transit::VehiclePositionQuery.new(
      at: Time.find_zone!("Asia/Taipei").local(2026, 8, 10, 12, 0, 0),
      route_ids: [ route.route_id ],
      datasets: [ active ]
    )

    assert_equal %w[inbound outbound], query.send(:vehicle_directions_for_route, route).sort
  end
end

class VehicleDensifyPlacementTest < ActiveSupport::TestCase
  test "express TRA trips interpolate through corridor stations" do
    route = TransitRoute.create!(
      system_id: "tra",
      route_id: "densify_vehicle_line",
      name: "密化測試線",
      line_ref: "DV",
      color: "#000000",
      geojson_path: "/geojson/does-not-exist.geojson"
    )
    %w[A B C D E].each_with_index do |ref, index|
      TransitRouteStation.create!(
        transit_route: route,
        station_ref: ref,
        name: ref,
        stop_sequence: index + 1,
        direction: TransitRoute::DIRECTION_BOTH
      )
    end

    dataset = ScheduleDataset.create!(name: "densify tdx", source: "tdx", active: true)
    calendar = ServiceCalendar.create!(schedule_dataset: dataset, code: "weekday", name: "平日")
    trip = ScheduleTrip.create!(
      schedule_dataset: dataset,
      transit_route: route,
      service_calendar: calendar,
      direction: "forward",
      train_number: "100",
      destination_name: "E"
    )
    TripStopTime.create!(schedule_trip: trip, station_ref: "A", stop_sequence: 1,
                         arrival_time: Time.utc(2000, 1, 1, 10, 0, 0), departure_time: Time.utc(2000, 1, 1, 10, 1, 0))
    TripStopTime.create!(schedule_trip: trip, station_ref: "E", stop_sequence: 2,
                         arrival_time: Time.utc(2000, 1, 1, 10, 40, 0), departure_time: Time.utc(2000, 1, 1, 10, 41, 0))

    at = Time.find_zone!("Asia/Taipei").local(2026, 8, 10, 10, 20, 0)
    vehicles = Transit::VehiclePositionQuery.new(at: at, route_ids: [ route.route_id ], datasets: [ dataset ]).call
    vehicle = vehicles.find { |row| row[:train_number] == "100" }

    assert vehicle, "expected densified express trip to appear"
    refute_equal [ "A", "E" ], [ vehicle[:from_station_ref], vehicle[:to_station_ref] ]
    assert_includes %w[A B C D E], vehicle[:from_station_ref]
    assert_includes %w[A B C D E], vehicle[:to_station_ref]
  end
end
