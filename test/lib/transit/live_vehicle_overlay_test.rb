# frozen_string_literal: true

require "test_helper"

class LiveVehicleOverlayTest < ActiveSupport::TestCase
  class FakeClient
    attr_reader :paths

    def initialize(responses = {})
      @responses = responses
      @paths = []
    end

    def configured?
      true
    end

    def fetch_all(path)
      @paths << path
      Array(@responses[path])
    end
  end

  class UnconfiguredClient
    def configured?
      false
    end

    def fetch_all(*)
      raise "should not fetch"
    end
  end

  setup do
    @now = Time.find_zone!("Asia/Taipei").local(2026, 8, 4, 12, 0, 0)
    travel_to @now
  end

  teardown do
    travel_back
    Rails.cache.clear
  end

  test "skips TDX when simulation time is far from now" do
    client = FakeClient.new("v3/Rail/TRA/TrainLiveBoard" => [
      { "TrainNo" => "110", "DelayTime" => 8, "StationID" => "1000", "TrainStationStatus" => 2 }
    ])
    vehicles = [ tra_vehicle(train_number: "110") ]

    Transit::LiveVehicleOverlay.apply!(
      vehicles,
      at: @now + 10.minutes,
      route_ids: [ "western_trunk_north" ],
      client: client
    )

    assert_empty client.paths
    assert_equal "none", vehicles.first[:delay_source]
    assert_equal 0, vehicles.first[:delay_seconds]
  end

  test "skips TDX when client is not configured" do
    vehicles = [ tra_vehicle(train_number: "110") ]

    Transit::LiveVehicleOverlay.apply!(
      vehicles,
      at: @now,
      route_ids: [ "western_trunk_north" ],
      client: UnconfiguredClient.new
    )

    assert_equal "none", vehicles.first[:delay_source]
  end

  test "applies TRA DelayTime and marks delay_source" do
    client = FakeClient.new("v3/Rail/TRA/TrainLiveBoard" => [
      { "TrainNo" => "110", "DelayTime" => 5, "StationID" => "1000", "TrainStationStatus" => 2 }
    ])

    vehicles = [ tra_vehicle(train_number: "110", id: "trip:999001") ]
    overlay = Transit::LiveVehicleOverlay.new(
      at: @now,
      route_ids: [ "western_trunk_north" ],
      client: client
    )
    overlay.define_singleton_method(:trip_stops) do |_trip_id|
      [
        { station_ref: "1000", arrival: 11 * 60 + 50, departure: 11 * 60 + 52 },
        { station_ref: "1001", arrival: 12 * 60 + 5, departure: 12 * 60 + 6 }
      ]
    end
    overlay.define_singleton_method(:attach_coords) { |_route, vehicle| vehicle }

    overlay.apply!(vehicles)

    vehicle = vehicles.first
    assert_equal "tdx_tra", vehicle[:delay_source]
    assert_equal 5 * 60, vehicle[:delay_seconds]
    assert_equal "timetable+live", vehicle[:position_source]
    assert_equal "delayed", vehicle[:status]
    assert_includes client.paths, "v3/Rail/TRA/TrainLiveBoard"
    assert overlay.meta[:tra]
  end

  test "forces dwell when TRA board says train is at station" do
    client = FakeClient.new("v3/Rail/TRA/TrainLiveBoard" => [
      { "TrainNo" => "210", "DelayTime" => 0, "StationID" => "1000", "TrainStationStatus" => 1 }
    ])

    vehicles = [ tra_vehicle(train_number: "210", id: "trip:999002") ]
    overlay = Transit::LiveVehicleOverlay.new(
      at: @now,
      route_ids: [ "western_trunk_north" ],
      client: client
    )
    overlay.define_singleton_method(:trip_stops) do |_trip_id|
      [
        { station_ref: "1000", arrival: 11 * 60 + 50, departure: 11 * 60 + 52 },
        { station_ref: "1001", arrival: 12 * 60 + 5, departure: 12 * 60 + 6 }
      ]
    end
    overlay.define_singleton_method(:attach_coords) { |_route, vehicle| vehicle }

    overlay.apply!(vehicles)

    vehicle = vehicles.first
    assert_equal "stopped", vehicle[:status]
    assert_in_delta 0.0, vehicle[:progress]
    assert_equal "1000", vehicle[:from_station_ref]
  end

  test "applies metro LiveBoard median shift" do
    client = FakeClient.new(
      "v2/Rail/Metro/LiveBoard/TRTC" => [
        {
          "LineID" => "BL",
          "StationID" => "BL08",
          "DestinationStationName" => { "Zh_tw" => "南港展覽館" },
          "EstimateTime" => 4
        }
      ]
    )

    vehicles = [ {
      id: "metro:1:outbound:南港展覽館:BL07:700",
      soft_id: "metro:1",
      train_number: nil,
      label: "往南港展覽館",
      route_id: "bannan",
      system_id: "taipei_metro",
      color: "#0070bd",
      from_station_ref: "BL07",
      to_station_ref: "BL08",
      progress: 0.5,
      delay_seconds: 0,
      status: "on_time",
      destination_name: "南港展覽館",
      position_source: "station_timetable",
      delay_source: "none",
      direction: "outbound",
      motion_departure_minutes: 11 * 60 + 58,
      motion_arrival_minutes: 12 * 60 + 2,
      departure_minutes: 11 * 60 + 58,
      arrival_minutes: 12 * 60 + 2
    } ]

    overlay = Transit::LiveVehicleOverlay.new(
      at: @now,
      route_ids: [ "bannan" ],
      client: client
    )
    overlay.define_singleton_method(:attach_coords) { |_route, vehicle| vehicle }
    overlay.apply!(vehicles)

    vehicle = vehicles.first
    # Board ETA 4 min vs scheduled remaining 2 min => ~+2 min late.
    assert_equal "tdx_metro_liveboard", vehicle[:delay_source]
    assert vehicle[:delay_seconds] > 60
    assert_equal "station_timetable+live", vehicle[:position_source]
    assert overlay.meta[:metro]
  end

  test "applies KLRT GPS coordinates when available" do
    client = FakeClient.new(
      "v2/Rail/Metro/LivePosition/KLRT" => [
        {
          "TripID" => "C01",
          "Direction" => 0,
          "TrainPosition" => { "PositionLat" => 22.63, "PositionLon" => 120.30 }
        }
      ]
    )

    vehicles = [ {
      id: "metro:klrt:1",
      route_id: "circular_lrt",
      system_id: "kaohsiung_metro",
      train_number: "C01",
      label: "環狀",
      from_station_ref: "C1",
      to_station_ref: "C2",
      progress: 0.3,
      delay_seconds: 0,
      status: "on_time",
      position_source: "headway_estimate",
      delay_source: "none",
      direction: "outbound",
      lat: 22.62,
      lng: 120.29
    } ]

    Transit::LiveVehicleOverlay.apply!(
      vehicles,
      at: @now,
      route_ids: [ "circular_lrt" ],
      client: client
    )

    vehicle = vehicles.first
    assert_equal "tdx_gps", vehicle[:position_source]
    assert_in_delta 22.63, vehicle[:lat]
    assert_in_delta 120.30, vehicle[:lng]
  end

  private

  def tra_vehicle(train_number:, id: "trip:1")
    {
      id: id,
      soft_id: id,
      train_number: train_number,
      label: train_number,
      route_id: "western_trunk_north",
      system_id: "tra",
      color: "#ff6600",
      from_station_ref: "1000",
      to_station_ref: "1001",
      progress: 0.4,
      delay_seconds: 0,
      status: "on_time",
      position_source: "timetable",
      delay_source: "none",
      direction: "outbound",
      motion_departure_minutes: 11 * 60 + 52,
      motion_arrival_minutes: 12 * 60 + 5,
      departure_minutes: 11 * 60 + 52,
      arrival_minutes: 12 * 60 + 5
    }
  end
end
