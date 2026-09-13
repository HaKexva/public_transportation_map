# frozen_string_literal: true

require "test_helper"

class Transit::StationInfoQueryTest < ActiveSupport::TestCase
  class FakeClient
    def initialize(payloads)
      @payloads = payloads
    end

    def configured?
      true
    end

    def get_json(path, query: {})
      key = [ path, query["$filter"] ]
      @payloads.fetch(key) { [] }
    end
  end

  setup do
    Rails.cache.clear
  end

  test "returns metro exits with accessibility summary" do
    client = FakeClient.new(
      {
        [ "v2/Rail/Metro/StationExit/TRTC", "StationID eq 'BL01'" ] => [
          {
            "StationID" => "BL01",
            "ExitID" => "1",
            "ExitName" => { "Zh_tw" => "1號出口" },
            "LocationDescription" => { "Zh_tw" => "中央路四段" },
            "Stair" => true,
            "Escalator" => true,
            "Elevator" => true,
            "ExitPosition" => { "PositionLon" => 121.42, "PositionLat" => 24.96 }
          }
        ]
      }
    )

    payload = Transit::StationInfoQuery.new(
      station_ref: "BL01",
      route_id: "bannan",
      client: client
    ).call

    assert_equal 1, payload[:exits].length
    assert_equal "1號出口", payload[:exits].first[:name]
    assert payload[:accessibility][:elevator]
    assert payload[:accessibility][:escalator]
    assert_equal "tdx_station_exit", payload[:source]
  end

  test "returns empty payload when ref missing" do
    payload = Transit::StationInfoQuery.new(station_ref: "", route_id: "bannan").call
    assert_equal [], payload[:exits]
    assert_equal "missing_ref", payload[:error]
  end
end
