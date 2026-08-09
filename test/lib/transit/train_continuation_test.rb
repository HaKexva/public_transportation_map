# frozen_string_literal: true

require "test_helper"

class TrainContinuationTest < ActiveSupport::TestCase
  setup do
    @west = TransitRoute.create!(
      system_id: "tra",
      route_id: "test_cont_west",
      name: "測試縱貫西",
      line_ref: "TCW"
    )
    @east = TransitRoute.create!(
      system_id: "tra",
      route_id: "test_cont_east",
      name: "測試台東線",
      line_ref: "TCE"
    )
    @dataset = ScheduleDataset.create!(name: "Continuation test", source: "manual")
    @calendar = ServiceCalendar.create!(
      schedule_dataset: @dataset,
      code: "weekday",
      name: "平日"
    )
  end

  test "matches next trip that starts at the same terminus within the window" do
    current = create_trip(@west, "111", destination: "花蓮")
    add_stops(current, [
      [ "1000", "11:00", "11:00" ],
      [ "1010", "11:30", "11:31" ],
      [ "7000;HUA", "12:00", "12:02" ]
    ])
    nxt = create_trip(@east, "412", destination: "台東")
    add_stops(nxt, [
      [ "7000", "12:08", "12:08" ],
      [ "8000", "13:40", "13:41" ]
    ])

    result = Transit::TrainContinuation.new(calendar_ids: [ @calendar.id ]).lookup(
      trip_id: current.id,
      train_number: "111",
      last_station_ref: "7000;HUA",
      arrival_minutes: 12 * 60
    )

    assert_equal "412", result[:train_number]
    assert_equal nxt.id, result[:trip_id]
    assert_equal "test_cont_east", result[:route_id]
    assert_in_delta 12 * 60 + 8, result[:departure_minutes]
  end

  test "prefers TDX note train number over a closer other departure" do
    current = create_trip(@west, "111", destination: "花蓮", notes: "本列車於花蓮站後改為412次")
    add_stops(current, [
      [ "1000", "11:00", "11:00" ],
      [ "7000", "12:00", "12:00" ]
    ])
    closer = create_trip(@east, "555", destination: "壽豐")
    add_stops(closer, [
      [ "7000", "12:04", "12:04" ],
      [ "7100", "12:20", "12:21" ]
    ])
    noted = create_trip(@east, "412", destination: "台東")
    add_stops(noted, [
      [ "7000", "12:10", "12:10" ],
      [ "8000", "13:40", "13:41" ]
    ])

    result = Transit::TrainContinuation.new(calendar_ids: [ @calendar.id ]).lookup(
      trip_id: current.id,
      train_number: "111",
      last_station_ref: "7000",
      arrival_minutes: 12 * 60,
      notes: current.notes
    )

    assert_equal "412", result[:train_number]
    assert_equal noted.id, result[:trip_id]
  end

  test "ignores a later departure outside the handoff window" do
    current = create_trip(@west, "111", destination: "花蓮")
    add_stops(current, [
      [ "1000", "11:00", "11:00" ],
      [ "7000", "12:00", "12:00" ]
    ])
    late = create_trip(@east, "412", destination: "台東")
    add_stops(late, [
      [ "7000", "12:40", "12:40" ],
      [ "8000", "14:10", "14:11" ]
    ])

    result = Transit::TrainContinuation.new(calendar_ids: [ @calendar.id ]).lookup(
      trip_id: current.id,
      train_number: "111",
      last_station_ref: "7000",
      arrival_minutes: 12 * 60
    )

    assert_nil result
  end

  test "falls back to note-only when the numbered trip is missing" do
    current = create_trip(@west, "111", destination: "花蓮", notes: "改駛200次")
    add_stops(current, [
      [ "1000", "11:00", "11:00" ],
      [ "7000", "12:00", "12:00" ]
    ])

    result = Transit::TrainContinuation.new(calendar_ids: [ @calendar.id ]).lookup(
      trip_id: current.id,
      train_number: "111",
      last_station_ref: "7000",
      arrival_minutes: 12 * 60,
      notes: current.notes
    )

    assert_equal "200", result[:train_number]
    assert_nil result[:trip_id]
    assert_nil result[:route_id]
  end

  test "wraps midnight when the next number leaves after 00:00" do
    current = create_trip(@west, "111", destination: "花蓮")
    add_stops(current, [
      [ "1000", "22:00", "22:00" ],
      [ "7000", "23:50", "23:50" ]
    ])
    nxt = create_trip(@east, "412", destination: "台東")
    add_stops(nxt, [
      [ "7000", "00:05", "00:05" ],
      [ "8000", "02:00", "02:01" ]
    ])

    result = Transit::TrainContinuation.new(calendar_ids: [ @calendar.id ]).lookup(
      trip_id: current.id,
      train_number: "111",
      last_station_ref: "7000",
      arrival_minutes: 23 * 60 + 50
    )

    assert_equal "412", result[:train_number]
    assert_equal nxt.id, result[:trip_id]
  end

  test "vehicle query attaches continues_as on the last hop" do
    current = create_trip(@west, "C9001", destination: "花蓮")
    add_stops(current, [
      [ "TC1000", "11:00", "11:00" ],
      [ "TC1010", "11:30", "11:31" ],
      [ "TC1020", "12:00", "12:02" ]
    ])
    nxt = create_trip(@east, "C9412", destination: "台東")
    add_stops(nxt, [
      [ "TC1020", "12:08", "12:08" ],
      [ "TC1030", "13:40", "13:41" ]
    ])

    at = Time.find_zone!("Asia/Taipei").local(2026, 8, 4, 11, 50, 0)
    vehicles = Transit::VehiclePositionQuery.new(
      at: at,
      route_ids: [ "test_cont_west" ],
      datasets: [ @dataset ]
    ).call

    vehicle = vehicles.find { |row| row[:train_number] == "C9001" }
    assert vehicle, "expected test train on last hop"
    assert_equal "C9412", vehicle.dig(:continues_as, :train_number)
    assert_equal nxt.id, vehicle.dig(:continues_as, :trip_id)
    assert_equal "test_cont_east", vehicle.dig(:continues_as, :route_id)
  end

  private

  def create_trip(route, train_number, destination:, notes: nil)
    ScheduleTrip.create!(
      schedule_dataset: @dataset,
      transit_route: route,
      service_calendar: @calendar,
      direction: "outbound",
      train_number: train_number,
      destination_name: destination,
      notes: notes
    )
  end

  def add_stops(trip, rows)
    rows.each_with_index do |(station_ref, arrival, departure), index|
      TripStopTime.create!(
        schedule_trip: trip,
        station_ref: station_ref,
        stop_sequence: index + 1,
        arrival_time: parse_clock(arrival),
        departure_time: parse_clock(departure)
      )
    end
  end

  def parse_clock(value)
    hour, min = value.split(":").map(&:to_i)
    Time.utc(2000, 1, 1, hour, min, 0)
  end
end
