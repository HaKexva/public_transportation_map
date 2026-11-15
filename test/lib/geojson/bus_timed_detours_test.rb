# frozen_string_literal: true

require "test_helper"

class GeojsonBusTimedDetoursTest < ActiveSupport::TestCase
  GATE = [ 121.58990, 25.07170 ].freeze
  CAMPUS_STOP = [ 121.59250, 25.07200 ].freeze

  test "keeps the campus loop as the main line and names the cut file with its hours" do
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
      assert_equal "28（08:00前、21:30後不繞駛三總）", plain["properties"]["name"]
      assert_equal "outside", plain["properties"]["campus_span"]
      assert_equal "08:00-21:30", plain["properties"]["detour_hours"]
      assert_equal [ "將軍嶺" ], plain["features"].select { |f| f["geometry"]["type"] == "Point" }.map { |f| f.dig("properties", "name") }
      assert plain["features"].first.dig("geometry", "coordinates").none? { |point| point[0] > 121.5915 }
      assert_equal "28", detour["properties"]["name"]
      assert_nil detour["properties"]["via"]
      assert_equal "inside", detour["properties"]["campus_span"]
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
    timed = "08:00前、21:30後不繞駛三總"
    assert_equal "617", Geojson::BusTimedDetours.base_name("617（#{timed}）", timed)
    assert_equal "繞駛行善路經金龍寺", Geojson::BusTimedDetours.base_via("繞駛行善路經金龍寺、#{timed}")
    assert_not Geojson::BusTimedDetours.detour?(timed)
  end

  test "617副 stays one campus route, including the 07:00 trip" do
    assert_nil Geojson::BusTimedDetours.hours_for("Taipei", "617副")

    Dir.mktmpdir do |dir|
      path = File.join(dir, "taipei_617sub.geojson")
      line = [ [ 121.58985, 25.06900 ], GATE, [ 121.59200, 25.07150 ], CAMPUS_STOP, [ 121.58980, 25.07500 ] ]
      File.write(path, JSON.generate(
        "id" => "taipei_617sub", "type" => "FeatureCollection", "name" => "617副",
        "properties" => {
          "id" => "taipei_617sub", "name" => "617副", "name_en" => "617Sub.",
          "ref" => "617副", "city_id" => "Taipei"
        },
        "features" => [
          { "type" => "Feature", "properties" => { "feature_type" => "route", "direction" => 0 },
            "geometry" => { "type" => "LineString", "coordinates" => line } }
        ]
      ))

      assert_not Geojson::BusTimedDetours.split!(path, router: Object.new)
      assert_empty Dir[File.join(dir, "taipei_617sub_*.geojson")]
      assert_equal line, JSON.parse(File.read(path)).dig("features", 0, "geometry", "coordinates")
    end
  end

  test "551 繞駛行善路經金龍寺 stays a single campus file with no 不繞駛 sibling" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "taipei_551_xingshan.geojson")
      line = [ [ 121.58985, 25.06900 ], GATE, [ 121.59200, 25.07150 ], CAMPUS_STOP, [ 121.59200, 25.07250 ],
               [ 121.58995, 25.07190 ], [ 121.58980, 25.07500 ] ]
      File.write(path, JSON.generate(
        "id" => "taipei_551_xingshan", "type" => "FeatureCollection", "name" => "551（繞駛行善路經金龍寺）",
        "properties" => {
          "id" => "taipei_551_xingshan", "name" => "551（繞駛行善路經金龍寺）", "name_en" => "551",
          "ref" => "551", "city_id" => "Taipei", "via" => "繞駛行善路經金龍寺", "daily_trips" => 1
        },
        "features" => [
          { "type" => "Feature", "properties" => { "feature_type" => "route", "direction" => 0 },
            "geometry" => { "type" => "LineString", "coordinates" => line } }
        ]
      ))

      assert Geojson::BusTimedDetours.no_outside_via?("繞駛行善路經金龍寺")
      assert Geojson::BusTimedDetours.split!(path, router: Object.new)
      assert_empty Dir[File.join(dir, "taipei_551_xingshan_*.geojson")]
      data = JSON.parse(File.read(path))
      assert_equal "inside", data.dig("properties", "campus_span")
      assert_equal "繞駛行善路經金龍寺", data.dig("properties", "via")
      assert_equal 1, data.dig("properties", "daily_trips")
    end
  end

  test "retitles the campus path as the main line and stamps the skip with its hours" do
    main = {
      "name" => "551（繞駛行善路經金龍寺、繞駛三總）",
      "properties" => {
        "id" => "taipei_551", "ref" => "551", "name" => "551（繞駛行善路經金龍寺、繞駛三總）",
        "name_en" => "551 (detour via Xingshan Road via Jinlong Temple, detour via Tri-Service General Hospital)",
        "via" => "繞駛行善路經金龍寺、繞駛三總",
        "via_en" => "detour via Xingshan Road via Jinlong Temple, detour via Tri-Service General Hospital",
        "detour_hours" => "08:00-21:30", "daily_trips" => 4
      },
      "features" => [ { "type" => "Feature", "properties" => { "name" => "551（繞駛行善路經金龍寺、繞駛三總）" }, "geometry" => { "type" => "LineString", "coordinates" => [] } } ]
    }
    skip = {
      "name" => "645副（不繞駛三總）",
      "properties" => {
        "id" => "taipei_645sub", "ref" => "645副", "name" => "645副（不繞駛三總）",
        "name_en" => "645副 (skips Tri-Service General Hospital)",
        "via" => "不繞駛三總", "via_en" => "skips Tri-Service General Hospital",
        "detour_hours" => "08:00-18:00", "daily_trips" => 3
      },
      "features" => []
    }

    assert Geojson::BusTimedDetours.retitle!(main)
    assert_equal "551（繞駛行善路經金龍寺）", main.dig("properties", "name")
    assert_equal "551 (detour via Xingshan Road via Jinlong Temple)", main.dig("properties", "name_en")
    assert_equal "inside", main.dig("properties", "campus_span")
    assert_equal 4, main.dig("properties", "daily_trips")
    assert_equal "551（繞駛行善路經金龍寺）", main.dig("features", 0, "properties", "name")

    assert Geojson::BusTimedDetours.retitle!(skip)
    assert_equal "645副（08:00前、18:00後不繞駛三總）", skip.dig("properties", "name")
    assert_equal "before 08:00 and after 18:00, skips Tri-Service General Hospital", skip.dig("properties", "via_en")
    assert_equal "outside", skip.dig("properties", "campus_span")
    assert_equal 3, skip.dig("properties", "daily_trips")
    assert_not Geojson::BusTimedDetours.retitle!(skip)
    assert_not Geojson::BusTimedDetours.retitle!(main)
  end

  test "617 campus trips skip the out-and-back to 福華商場" do
    junction = [ 121.59073, 25.06903 ]
    mall = [ 121.59362, 25.06897 ]
    east = [ 121.59508, 25.06870 ]
    west = [ 121.58816, 25.06911 ]
    line = [ [ 121.59076, 25.06912 ], junction, [ 121.59373, 25.06894 ], east, mall, junction.dup, west ]
    data = {
      "properties" => { "ref" => "617", "campus_span" => "inside" },
      "features" => [
        { "type" => "Feature", "properties" => { "feature_type" => "route", "direction" => 1 },
          "geometry" => { "type" => "LineString", "coordinates" => line } },
        { "type" => "Feature", "properties" => { "feature_type" => "station", "name" => "福華商場", "direction" => 1 },
          "geometry" => { "type" => "Point", "coordinates" => mall } },
        { "type" => "Feature", "properties" => { "feature_type" => "station", "name" => "內湖行政大樓", "direction" => 1 },
          "geometry" => { "type" => "Point", "coordinates" => west } }
      ]
    }

    assert Geojson::BusTimedDetours.drop_inside_skips!(data)

    kept = data["features"].find { |feature| feature.dig("geometry", "type") == "LineString" }
    coords = kept.dig("geometry", "coordinates")
    names = data["features"].select { |feature| feature.dig("geometry", "type") == "Point" }.map { |feature| feature.dig("properties", "name") }
    assert_equal [ "內湖行政大樓" ], names
    assert_equal west, coords.last
    assert coords.none? { |point| point[0] > 121.592 }
    assert_not Geojson::BusTimedDetours.drop_inside_skips!(data)
  end

  test "617 campus trips drop the turnaround past 福華商場 and keep the hospital" do
    campus = [ 121.59210, 25.07185 ]
    junction = [ 121.59073, 25.06903 ]
    toward_mall = [ 121.59191, 25.06900 ]
    mall = [ 121.59362, 25.06897 ]
    past_mall = [ 121.59545, 25.06855 ]
    west = [ 121.58816, 25.06911 ]
    line = [ campus, junction, toward_mall, mall, past_mall, mall.dup, toward_mall.dup, junction.dup, west ]
    data = {
      "properties" => { "ref" => "617", "campus_span" => "inside" },
      "features" => [
        { "type" => "Feature", "properties" => { "feature_type" => "route", "direction" => 1 },
          "geometry" => { "type" => "LineString", "coordinates" => line } },
        { "type" => "Feature", "properties" => { "feature_type" => "station", "name" => "福華商場", "direction" => 1 },
          "geometry" => { "type" => "Point", "coordinates" => mall } },
        { "type" => "Feature", "properties" => { "feature_type" => "station", "name" => "三總內湖站", "direction" => 1 },
          "geometry" => { "type" => "Point", "coordinates" => campus } }
      ]
    }

    assert Geojson::BusTimedDetours.drop_inside_skips!(data)

    coords = data["features"].find { |feature| feature.dig("geometry", "type") == "LineString" }.dig("geometry", "coordinates")
    assert_includes coords, campus
    assert_equal west, coords.last
    assert coords.none? { |point| point[1] < 25.070 && point[0] > 121.591 }
  end

  test "a campus trip that drives past 福華商場 drops the stop and keeps the road" do
    campus = [ 121.59210, 25.07185 ]
    mall = [ 121.59362, 25.06897 ]
    east = [ 121.60000, 25.06720 ]
    line = [ [ 121.58816, 25.06911 ], mall, east, campus ]
    data = {
      "properties" => { "ref" => "617副" },
      "features" => [
        { "type" => "Feature", "properties" => { "feature_type" => "route", "direction" => 0 },
          "geometry" => { "type" => "LineString", "coordinates" => line } },
        { "type" => "Feature", "properties" => { "feature_type" => "station", "name" => "福華商場", "direction" => 0 },
          "geometry" => { "type" => "Point", "coordinates" => mall } }
      ]
    }

    assert Geojson::BusTimedDetours.drop_inside_skips!(data)

    coords = data["features"].find { |feature| feature.dig("geometry", "type") == "LineString" }.dig("geometry", "coordinates")
    names = data["features"].select { |feature| feature.dig("geometry", "type") == "Point" }.map { |feature| feature.dig("properties", "name") }
    assert_empty names
    assert_equal line, coords
  end

  test "off-hours trips that skip 三總 still stop at 福華商場" do
    mall = [ 121.59362, 25.06897 ]
    data = {
      "properties" => { "ref" => "645", "campus_span" => "outside" },
      "features" => [
        { "type" => "Feature", "properties" => { "feature_type" => "route", "direction" => 0 },
          "geometry" => { "type" => "LineString", "coordinates" => [ [ 121.59613, 25.06831 ], mall, [ 121.58822, 25.06918 ] ] } },
        { "type" => "Feature", "properties" => { "feature_type" => "station", "name" => "福華商場", "direction" => 0 },
          "geometry" => { "type" => "Point", "coordinates" => mall } }
      ]
    }

    assert_not Geojson::BusTimedDetours.drop_inside_skips!(data)
    assert_equal [ "福華商場" ], data["features"].select { |feature| feature.dig("geometry", "type") == "Point" }.map { |feature| feature.dig("properties", "name") }
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
