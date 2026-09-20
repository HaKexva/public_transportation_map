# frozen_string_literal: true

require "test_helper"

class GeojsonBusLoopCloserTest < ActiveSupport::TestCase
  test "merges nearby multiline fragments into one chain" do
    a = [ [ 121.0, 25.0 ], [ 121.001, 25.0 ] ]
    b = [ [ 121.0011, 25.0 ], [ 121.002, 25.0 ] ]

    merged = Geojson::BusLoopCloser.merge_line_strings([ a, b ])
    assert_equal 4, merged.length
    assert_in_delta 121.0, merged.first[0], 0.0001
    assert_in_delta 121.002, merged.last[0], 0.0001
  end

  test "closes nearly closed loop coordinates" do
    coords = [
      [ 121.0, 25.0 ],
      [ 121.001, 25.0 ],
      [ 121.001, 25.001 ],
      [ 121.00005, 25.00005 ]
    ]

    closed = Geojson::BusLoopCloser.close_loop_coordinates(coords, force: true)
    assert_equal coords.first, closed.last
    assert Geojson::BusLoopCloser.nearly_closed?(closed)
  end

  test "process_collection merges same-direction route parts and marks loop" do
    data = {
      "properties" => { "id" => "demo_loop" },
      "features" => [
        {
          "type" => "Feature",
          "properties" => { "feature_type" => "route", "direction" => 0, "ref" => "L1" },
          "geometry" => {
            "type" => "LineString",
            "coordinates" => [ [ 121.0, 25.0 ], [ 121.001, 25.0 ] ]
          }
        },
        {
          "type" => "Feature",
          "properties" => { "feature_type" => "route", "direction" => 0, "ref" => "L1" },
          "geometry" => {
            "type" => "LineString",
            "coordinates" => [ [ 121.0011, 25.0 ], [ 121.0, 25.00005 ] ]
          }
        },
        {
          "type" => "Feature",
          "properties" => { "feature_type" => "station", "direction" => 0, "ref" => "A", "name" => "總站" },
          "geometry" => { "type" => "Point", "coordinates" => [ 121.0, 25.0 ] }
        },
        {
          "type" => "Feature",
          "properties" => { "feature_type" => "station", "direction" => 0, "ref" => "B", "name" => "中間" },
          "geometry" => { "type" => "Point", "coordinates" => [ 121.001, 25.0 ] }
        },
        {
          "type" => "Feature",
          "properties" => { "feature_type" => "station", "direction" => 0, "ref" => "A", "name" => "總站" },
          "geometry" => { "type" => "Point", "coordinates" => [ 121.0, 25.0 ] }
        }
      ]
    }

    assert Geojson::BusLoopCloser.process_collection!(data)
    routes = data["features"].select { |feature| feature.dig("properties", "feature_type") == "route" }
    assert_equal 1, routes.length
    assert routes.first.dig("properties", "loop")
    assert_equal routes.first.dig("geometry", "coordinates").first,
      routes.first.dig("geometry", "coordinates").last
  end
end
