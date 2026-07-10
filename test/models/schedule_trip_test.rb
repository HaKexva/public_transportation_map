# frozen_string_literal: true

require "test_helper"

class ScheduleTripTest < ActiveSupport::TestCase
  setup do
    @route = TransitRoute.create!(
      system_id: "tra",
      route_id: "western_trunk_north",
      name: "縱貫線北段",
      line_ref: "WN"
    )
    @dataset = ScheduleDataset.create!(name: "Test dataset", source: "manual")
    @calendar = ServiceCalendar.create!(
      schedule_dataset: @dataset,
      code: "weekday",
      name: "平日"
    )
    @trip = ScheduleTrip.create!(
      schedule_dataset: @dataset,
      transit_route: @route,
      service_calendar: @calendar,
      direction: "southbound",
      train_number: "133"
    )
  end

  test "ordered stop times follow stop sequence" do
    TripStopTime.create!(
      schedule_trip: @trip,
      station_ref: "1000",
      stop_sequence: 1,
      departure_time: Time.zone.parse("08:00")
    )
    TripStopTime.create!(
      schedule_trip: @trip,
      station_ref: "1010",
      stop_sequence: 2,
      arrival_time: Time.zone.parse("08:05")
    )

    assert_equal %w[1000 1010], @trip.ordered_stop_times.map(&:station_ref)
  end
end
