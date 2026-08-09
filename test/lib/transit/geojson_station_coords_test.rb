# frozen_string_literal: true

require "test_helper"

class GeojsonStationCoordsTest < ActiveSupport::TestCase
  setup do
    Transit::GeojsonStationCoords.clear_cache!
    @route = TransitRoute.create!(
      system_id: "tra",
      route_id: "test_station_name_wtn",
      name: "縱貫線（北段）",
      line_ref: "WN",
      geojson_path: "/geojson/tra/western_trunk_north.geojson"
    )
  end

  teardown do
    Transit::GeojsonStationCoords.clear_cache!
  end

  test "lookup_name resolves composite transfer refs to a station name" do
    name = Transit::GeojsonStationCoords.lookup_name(@route, "1000;R10;BL12;02")
    assert_equal "臺北", name
  end

  test "lookup_name accepts a numeric TRA token" do
    name = Transit::GeojsonStationCoords.lookup_name(@route, "1020")
    assert_equal "板橋", name
  end
end
