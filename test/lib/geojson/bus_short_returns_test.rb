# frozen_string_literal: true

require "test_helper"

class GeojsonBusShortReturnsTest < ActiveSupport::TestCase
  test "531 short return clips inbound at 新明成功路口" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "taipei_531.geojson")
      tip = [ 121.590623, 25.06008 ]
      beyond = [ 121.580000, 25.07000 ]
      File.write(path, JSON.generate(
        "id" => "taipei_531", "type" => "FeatureCollection", "name" => "531",
        "properties" => {
          "id" => "taipei_531", "name" => "531", "name_en" => "531", "ref" => "531", "city_id" => "Taipei"
        },
        "features" => [
          { "type" => "Feature",
            "properties" => { "feature_type" => "route", "direction" => 0, "name" => "531" },
            "geometry" => { "type" => "LineString", "coordinates" => [ [ 121.62, 25.08 ], [ 121.55, 25.06 ] ] } },
          { "type" => "Feature",
            "properties" => { "feature_type" => "route", "direction" => 1, "name" => "531" },
            "geometry" => { "type" => "LineString", "coordinates" => [ [ 121.55, 25.06 ], tip, beyond ] } },
          { "type" => "Feature",
            "properties" => { "feature_type" => "station", "name" => "松山車站", "direction" => 1 },
            "geometry" => { "type" => "Point", "coordinates" => [ 121.55, 25.06 ] } },
          { "type" => "Feature",
            "properties" => { "feature_type" => "station", "name" => "新明成功路口", "direction" => 1 },
            "geometry" => { "type" => "Point", "coordinates" => tip } },
          { "type" => "Feature",
            "properties" => { "feature_type" => "station", "name" => "紫雲里", "direction" => 1 },
            "geometry" => { "type" => "Point", "coordinates" => beyond } }
        ]
      ))

      assert Geojson::BusShortReturns.split!(path, Geojson::BusShortReturns::ENTRIES["taipei_531"])
      short_path = Dir[File.join(dir, "taipei_531_*.geojson")].first
      assert short_path
      short = JSON.parse(File.read(short_path))
      assert_equal "返程至新明成功路口", short.dig("properties", "via")
      assert_equal 2, short.dig("properties", "daily_trips")
      inbound = short["features"].find { |f| f.dig("geometry", "type") == "LineString" && f.dig("properties", "direction") == 1 }
      assert_equal tip, inbound.dig("geometry", "coordinates").last
      stops = short["features"].select { |f| f.dig("geometry", "type") == "Point" && f.dig("properties", "direction") == 1 }
        .map { |f| f.dig("properties", "name") }
      assert_equal [ "松山車站", "新明成功路口" ], stops
    end
  end
end
