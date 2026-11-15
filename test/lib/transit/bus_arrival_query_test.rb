# frozen_string_literal: true

require "test_helper"

class TransitBusArrivalQueryTest < ActiveSupport::TestCase
  class FakeClient
    def initialize(rows)
      @rows = rows
    end

    def configured?
      true
    end

    def get_json(path, query: {})
      @last_path = path
      @last_query = query
      @rows
    end

    attr_reader :last_path, :last_query
  end

  test "returns sorted ETA rows for a stop uid" do
    client = FakeClient.new([
      {
        "RouteName" => { "Zh_tw" => "12" },
        "Direction" => 0,
        "EstimateTime" => 600,
        "StopStatus" => 0,
        "StopUID" => "TAO1271",
        "DestinationStopName" => { "Zh_tw" => "中壢" },
        "RouteUID" => "TAO12"
      },
      {
        "RouteName" => { "Zh_tw" => "208A" },
        "Direction" => 1,
        "EstimateTime" => 120,
        "StopStatus" => 0,
        "StopUID" => "TAO1271",
        "RouteUID" => "TAO2081"
      }
    ])

    payload = Transit::BusArrivalQuery.new(
      city_id: "Taoyuan",
      stop_uid: "TAO1271",
      client: client
    ).call

    assert_equal 2, payload[:arrivals].length
    assert_equal "208A", payload[:arrivals].first[:route_name]
    assert_equal 120, payload[:arrivals].first[:estimate_seconds]
    assert_equal 2.0, payload[:arrivals].first[:estimate_minutes]
    assert_includes client.last_path, "City/Taoyuan"
    assert_includes client.last_query["$filter"], "StopUID eq 'TAO1271'"
  end

  test "uses InterCity path for highway buses" do
    client = FakeClient.new([])
    Transit::BusArrivalQuery.new(city_id: "InterCity", stop_uid: "THB123", client: client).call
    assert_equal "v2/Bus/EstimatedTimeOfArrival/InterCity", client.last_path
  end

  test "station board lists every route serving the pole by stop name" do
    client = FakeClient.new([
      { "RouteName" => { "Zh_tw" => "8" }, "Direction" => 0, "EstimateTime" => 900, "StopStatus" => 0, "StopUID" => "NWT186099" },
      { "RouteName" => { "Zh_tw" => "923" }, "Direction" => 1, "EstimateTime" => 300, "StopStatus" => 0, "StopUID" => "NWT1" },
      { "RouteName" => { "Zh_tw" => "999" }, "Direction" => 0, "EstimateTime" => 60, "StopStatus" => 0, "StopUID" => "NWT2" }
    ])

    payload = Transit::BusArrivalQuery.new(
      city_id: "NewTaipei",
      stop_uid: "NWT186099",
      stop_name: "捷運新店站(新店路)",
      route_names: %w[8 923],
      client: client
    ).call

    assert_equal %w[923 8], payload[:arrivals].map { |row| row[:route_name] }
    assert_includes client.last_query["$filter"], "StopName/Zh_tw eq '捷運新店站(新店路)'"
  end

  test "returns empty payload without stop uid" do
    payload = Transit::BusArrivalQuery.new(city_id: "Taoyuan", stop_uid: "", client: FakeClient.new([])).call
    assert_equal [], payload[:arrivals]
    assert_equal "missing_stop", payload[:error]
  end
end
