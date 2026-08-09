# frozen_string_literal: true

require "test_helper"

class ScheduleSnapshotTest < ActiveSupport::TestCase
  setup do
    @route = TransitRoute.create!(
      system_id: "tra",
      route_id: "test_snapshot_line",
      name: "測試快照線",
      line_ref: "TS",
      color: "#004B87",
      geojson_path: "/geojson/does-not-exist.geojson"
    )
    %w[A B C D].each_with_index do |ref, index|
      TransitRouteStation.create!(
        transit_route: @route,
        station_ref: ref,
        name: "站#{ref}",
        stop_sequence: index + 1,
        direction: TransitRoute::DIRECTION_BOTH
      )
    end
    @dataset = ScheduleDataset.create!(name: "Snapshot test", source: "manual", active: true)
    @calendar = ServiceCalendar.create!(
      schedule_dataset: @dataset,
      code: "weekday",
      name: "平日"
    )
    trip = ScheduleTrip.create!(
      schedule_dataset: @dataset,
      transit_route: @route,
      service_calendar: @calendar,
      direction: "outbound",
      train_number: "1001",
      destination_name: "丁",
      trip_type: "自強"
    )
    add_stop(trip, "A", "10:00", "10:01", 1)
    add_stop(trip, "D", "10:40", "10:41", 2)
  end

  test "returns densified trips for the service date" do
    date = Date.new(2026, 8, 4) # Tuesday
    payload = Transit::ScheduleSnapshot.new(date: date, route_ids: [ "test_snapshot_line" ]).call

    assert_equal "2026-08-04", payload[:date]
    route = payload[:routes].first
    assert_equal "test_snapshot_line", route[:route_id]
    trip = route[:trips].first
    assert_equal "1001", trip[:train_number]
    assert_equal "自強", trip[:trip_type]
    refs = trip[:path].map { |stop| stop[:r] }
    assert_equal %w[A B C D], refs
    assert trip[:path][1][:t]
    assert_in_delta 600.0, trip[:path][0][:a], 0.01
    assert_in_delta 601.0, trip[:path][0][:d], 0.01
  end

  test "returns empty routes when date has no calendar" do
    payload = Transit::ScheduleSnapshot.new(date: Date.new(2026, 8, 8), route_ids: [ "test_snapshot_line" ]).call
    # Saturday uses saturday/daily codes, not weekday.
    assert_equal [], payload[:routes]
  end

  test "returns empty payload without route ids" do
    payload = Transit::ScheduleSnapshot.new(date: Date.new(2026, 8, 4), route_ids: []).call
    assert_equal [], payload[:routes]
  end

  private

  def add_stop(trip, ref, arrival, departure, sequence)
    TripStopTime.create!(
      schedule_trip: trip,
      station_ref: ref,
      stop_sequence: sequence,
      arrival_time: parse_clock(arrival),
      departure_time: parse_clock(departure)
    )
  end

  def parse_clock(value)
    hour, min = value.split(":").map(&:to_i)
    Time.utc(2000, 1, 1, hour, min, 0)
  end
end
