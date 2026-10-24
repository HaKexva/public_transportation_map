# frozen_string_literal: true

require "test_helper"

class Transit::StationInfoQueryTest < ActiveSupport::TestCase
  test "returns stored metro exits with accessibility summary" do
    Transit::StationInfoImporter.store_system!(
      "TRTC",
      exits: [
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
      ],
      facilities: [
        {
          "StationID" => "BL01",
          "Elevators" => [ { "Description" => "往月台", "FloorLevel" => "B1" } ],
          "Toilets" => [ { "Description" => "付費區外", "FloorLevel" => "1F" } ],
          "InformationSpots" => [ { "Description" => "詢問處", "FloorLevel" => "1F" } ],
          "DrinkingFountains" => []
        }
      ]
    )

    payload = Transit::StationInfoQuery.new(station_ref: "BL01", route_id: "bannan").call

    assert_nil payload[:error]
    assert_equal 1, payload[:exits].length
    assert_equal "1號出口", payload[:exits].first[:name]
    assert payload[:accessibility][:elevator]
    assert payload[:accessibility][:escalator]
    assert payload[:accessibility][:toilet]
    assert_equal 3, payload[:facilities].length
    assert_includes payload[:source], "tdx_station_exit"
    assert_includes payload[:source], "tdx_station_facility"
  end

  test "returns an empty payload when nothing is stored" do
    payload = Transit::StationInfoQuery.new(station_ref: "BL02", route_id: "bannan").call

    assert_nil payload[:error]
    assert_equal [], payload[:exits]
    assert_equal [], payload[:facilities]
  end

  test "returns empty payload when ref missing" do
    payload = Transit::StationInfoQuery.new(station_ref: "", route_id: "bannan").call
    assert_equal [], payload[:exits]
    assert_equal "missing_ref", payload[:error]
  end
end
