# frozen_string_literal: true

require "test_helper"

class GeojsonBusTimedDetoursTest < ActiveSupport::TestCase
  GATE = [ 121.58990, 25.07170 ].freeze
  CAMPUS_STOP = [ 121.59250, 25.07200 ].freeze

  test "cuts the campus loop into a 不繞駛三總 file and keeps the loop as 繞駛三總" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "taipei_28.geojson")
      line = [ [ 121.58985, 25.06900 ], GATE, [ 121.59200, 25.07150 ], CAMPUS_STOP, [ 121.59200, 25.07250 ],
               [ 121.58995, 25.07190 ], [ 121.58980, 25.07500 ] ]
      File.write(path, JSON.generate(
        "id" => "taipei_28", "type" => "FeatureCollection", "name" => "28",
        "properties" => { "id" => "taipei_28", "name" => "28", "name_en" => "28", "ref" => "28", "city_id" => "Taipei" },
        "features" => [
          { "type" => "Feature", "properties" => { "feature_type" => "route", "direction" => 0 }, "geometry" => { "type" => "LineString", "coordinates" => line } },
          { "type" => "Feature", "properties" => { "feature_type" => "station", "name" => "三總內湖站", "direction" => 0 }, "geometry" => { "type" => "Point", "coordinates" => CAMPUS_STOP } },
          { "type" => "Feature", "properties" => { "feature_type" => "station", "name" => "將軍嶺", "direction" => 0 }, "geometry" => { "type" => "Point", "coordinates" => [ 121.58980, 25.07500 ] } }
        ]
      ))

      assert Geojson::BusTimedDetours.split!(path, router: Object.new)

      plain = JSON.parse(File.read(path))
      detour = JSON.parse(File.read(Dir[File.join(dir, "taipei_28_*.geojson")].first))
      assert_equal "28（不繞駛三總）", plain["properties"]["name"]
      assert_equal "08:00-21:30", plain["properties"]["detour_hours"]
      assert_equal [ "將軍嶺" ], plain["features"].select { |f| f["geometry"]["type"] == "Point" }.map { |f| f.dig("properties", "name") }
      assert plain["features"].first.dig("geometry", "coordinates").none? { |point| point[0] > 121.5915 }
      assert_equal "28（繞駛三總）", detour["properties"]["name"]
      assert_equal line, detour["features"].first.dig("geometry", "coordinates")
      assert_not Geojson::BusTimedDetours.split!(path, router: Object.new), "already split"
    end
  end

  test "compound labels keep the existing variant label for timetable matching" do
    via = "繞駛行善路經金龍寺、不繞駛三總"

    assert_not Geojson::BusTimedDetours.detour?(via)
    assert Geojson::BusTimedDetours.detour?("繞駛行善路經金龍寺、繞駛三總")
    assert_equal "繞駛行善路經金龍寺", Geojson::BusTimedDetours.base_via(via)
    assert_equal "551（繞駛行善路經金龍寺）", Geojson::BusTimedDetours.base_name("551（#{via}）", via)
    assert_nil Geojson::BusTimedDetours.base_via("不繞駛三總")
    assert_equal "617", Geojson::BusTimedDetours.base_name("617（不繞駛三總）", "不繞駛三總")
  end

  test "clips timetables and headway bands to inside or outside the detour hours" do
    weekday = { "Wednesday" => 1 }
    rows = [ {
      "Direction" => 0,
      "Timetables" => [ "07:30", "08:30", "22:00" ].map { |time| { "ServiceDay" => weekday, "StopTimes" => [ { "DepartureTime" => time } ] } },
      "Frequencys" => [ { "ServiceDay" => weekday, "StartTime" => "07:00", "EndTime" => "09:00", "MinHeadwayMins" => 30, "MaxHeadwayMins" => 30 } ]
    } ]

    inside = Geojson::BusServiceDays.clip_rows(rows, "08:00-21:30", inside: true)
    outside = Geojson::BusServiceDays.clip_rows(rows, "08:00-21:30", inside: false)

    assert_equal 1 + 2, Geojson::BusServiceDays.daily_trips(inside)
    assert_equal 2 + 2, Geojson::BusServiceDays.daily_trips(outside)
  end
end
