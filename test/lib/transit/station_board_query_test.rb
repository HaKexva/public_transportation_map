# frozen_string_literal: true

require "test_helper"

class StationBoardQueryTest < ActiveSupport::TestCase
  setup do
    @route = TransitRoute.create!(
      system_id: "tra",
      route_id: "board_test_line",
      name: "時刻測試線",
      line_ref: "BT",
      color: "#004B87",
      geojson_path: "/geojson/does-not-exist.geojson"
    )
    %w[1000 1020].each_with_index do |ref, index|
      TransitRouteStation.create!(
        transit_route: @route,
        station_ref: ref,
        name: "站#{ref}",
        stop_sequence: index + 1,
        direction: TransitRoute::DIRECTION_BOTH
      )
    end
    @dataset = ScheduleDataset.create!(name: "Board test", source: "manual", active: true)
    @calendar = ServiceCalendar.create!(schedule_dataset: @dataset, code: "weekday", name: "平日")
    @trip = ScheduleTrip.create!(
      schedule_dataset: @dataset,
      transit_route: @route,
      service_calendar: @calendar,
      direction: "outbound",
      train_number: "133",
      destination_name: "高雄"
    )
    TripStopTime.create!(
      schedule_trip: @trip,
      station_ref: "1000",
      stop_sequence: 1,
      arrival_time: Time.zone.local(2000, 1, 1, 12, 0, 0),
      departure_time: Time.zone.local(2000, 1, 1, 12, 2, 0)
    )
    TripStopTime.create!(
      schedule_trip: @trip,
      station_ref: "R10;BL12",
      stop_sequence: 2,
      arrival_time: Time.zone.local(2000, 1, 1, 12, 10, 0),
      departure_time: Time.zone.local(2000, 1, 1, 12, 12, 0)
    )
  end

  test "returns upcoming arrival and departure at a station" do
    at = Time.find_zone!("Asia/Taipei").local(2026, 8, 10, 11, 50, 0)
    query = Transit::StationBoardQuery.new(at: at, station_ref: "1000", route_ids: [ "board_test_line" ], datasets: [ @dataset ])
    payload = query.call

    stop = payload[:stops].first
    assert stop
    assert_equal "133", stop[:train_number]
    assert_equal "高雄", stop[:destination_name]
    assert_equal "12:00", stop[:arrival]
    assert_equal "12:02", stop[:departure]
  end

  test "matches composite station refs by token" do
    at = Time.find_zone!("Asia/Taipei").local(2026, 8, 10, 12, 0, 0)
    payload = Transit::StationBoardQuery.new(at: at, station_ref: "BL12", route_ids: [ "board_test_line" ], datasets: [ @dataset ]).call

    assert_equal 1, payload[:stops].length
    assert_equal "12:10", payload[:stops].first[:arrival]
    assert_equal "12:12", payload[:stops].first[:departure]
  end

  test "hides past trains outside the window" do
    at = Time.find_zone!("Asia/Taipei").local(2026, 8, 10, 18, 0, 0)
    payload = Transit::StationBoardQuery.new(at: at, station_ref: "1000", route_ids: [ "board_test_line" ], datasets: [ @dataset ]).call

    assert_equal [], payload[:stops]
  end

  test "falls back to headway estimates when a line has no stop times" do
    metro = TransitRoute.create!(
      system_id: "taipei_metro",
      route_id: "board_headway_line",
      name: "班距測試線",
      line_ref: "BR",
      color: "#c48c31",
      geojson_path: "/geojson/does-not-exist.geojson"
    )
    TransitRouteStation.create!(
      transit_route: metro,
      station_ref: "BR11;G16",
      name: "南京復興",
      stop_sequence: 1,
      direction: TransitRoute::DIRECTION_BOTH
    )
    HeadwayRule.create!(
      schedule_dataset: @dataset,
      transit_route: metro,
      service_calendar: @calendar,
      direction: "outbound",
      starts_at: Time.zone.local(2000, 1, 1, 6, 0, 0),
      ends_at: Time.zone.local(2000, 1, 1, 23, 0, 0),
      interval_seconds: 240
    )

    at = Time.find_zone!("Asia/Taipei").local(2026, 8, 10, 9, 50, 0)
    payload = Transit::StationBoardQuery.new(at: at, station_ref: "BR11", route_ids: [ "board_headway_line" ], datasets: [ @dataset ]).call

    assert payload[:stops].any?
    assert payload[:stops].all? { |stop| stop[:source] == "headway_estimate" }
    assert payload[:stops].all? { |stop| stop[:departure].present? }
  end

  test "period bounds include trains earlier in the selected day" do
    at = Time.find_zone!("Asia/Taipei").local(2026, 8, 10, 18, 0, 0)
    payload = Transit::StationBoardQuery.new(
      at: at,
      station_ref: "1000",
      route_ids: [ "board_test_line" ],
      datasets: [ @dataset ],
      from_minutes: 0,
      until_minutes: 1440
    ).call

    assert_equal 1, payload[:stops].length
    assert_equal "12:02", payload[:stops].first[:departure]
  end

  test "period bounds exclude trains outside the slot" do
    at = Time.find_zone!("Asia/Taipei").local(2026, 8, 10, 8, 0, 0)
    payload = Transit::StationBoardQuery.new(
      at: at,
      station_ref: "1000",
      route_ids: [ "board_test_line" ],
      datasets: [ @dataset ],
      from_minutes: 18 * 60,
      until_minutes: 21 * 60
    ).call

    assert_equal [], payload[:stops]
  end
end

class Api::StationBoardsControllerTest < ActionDispatch::IntegrationTest
  test "index returns empty stops without a ref" do
    get api_station_boards_url, params: { at: "2026-08-10T04:00:00Z" }
    assert_response :success
    assert_equal [], JSON.parse(response.body)["stops"]
  end

  test "index rejects invalid at" do
    get api_station_boards_url, params: { at: "nope", ref: "1000" }
    assert_response :bad_request
  end

  test "index accepts period bounds" do
    get api_station_boards_url, params: { at: "2026-08-10T04:00:00Z", ref: "1000", from: 0, until: 1440 }
    assert_response :success
    assert_kind_of Array, JSON.parse(response.body)["stops"]
  end

  test "expands airport_mrt_express to airport_mrt schedule trips" do
    assert_equal [ "airport_mrt" ], Transit::StationBoardQuery.expand_route_ids([ "airport_mrt_express" ])
    assert_equal [ "airport_mrt", "board_test_line" ], Transit::StationBoardQuery.expand_route_ids([ "airport_mrt_express", "board_test_line" ])
  end
end
