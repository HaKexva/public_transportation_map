# frozen_string_literal: true

require "test_helper"

class ScheduleDatasetTest < ActiveSupport::TestCase
  test "activate! does not deactivate other sources" do
    manual = ScheduleDataset.create!(name: "林鐵", source: "manual", active: true)
    tdx = ScheduleDataset.create!(name: "TDX", source: "tdx", active: false)

    tdx.activate!

    assert tdx.reload.active?
    assert manual.reload.active?
  end

  test "discard_replaced! destroys other rows of the same source" do
    keep = ScheduleDataset.create!(name: "TDX new", source: "tdx", active: true)
    old = ScheduleDataset.create!(name: "TDX old", source: "tdx", active: false)
    manual = ScheduleDataset.create!(name: "糖鐵", source: "manual", active: true)

    ScheduleDataset.discard_replaced!(source: "tdx", keep_id: keep.id)

    assert ScheduleDataset.exists?(keep.id)
    refute ScheduleDataset.exists?(old.id)
    assert ScheduleDataset.exists?(manual.id)
  end

  test "discard_inactive! deletes failed imports and their stop times" do
    live = ScheduleDataset.create!(name: "TDX live", source: "tdx", active: true, imported_at: Time.current)
    stale = ScheduleDataset.create!(name: "TDX failed", source: "tdx", active: false)
    calendar = stale.service_calendars.create!(code: "date_2026-10-04", name: "2026-10-04")
    route = TransitRoute.create!(system_id: "hsr", route_id: "taiwan_hsr_discard_test", line_ref: "THSR", name: "高鐵")
    trip = stale.schedule_trips.create!(
      transit_route: route,
      service_calendar: calendar,
      direction: "forward",
      train_number: "1"
    )
    TripStopTime.create!(schedule_trip: trip, station_ref: "02", stop_sequence: 1, departure_time: Time.zone.parse("06:00"))

    assert_equal 1, ScheduleDataset.discard_inactive!(source: "tdx")

    assert ScheduleDataset.exists?(live.id)
    refute ScheduleDataset.exists?(stale.id)
    refute TripStopTime.exists?(schedule_trip_id: trip.id)
  end
end
