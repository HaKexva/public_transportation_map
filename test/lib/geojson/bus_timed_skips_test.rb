# frozen_string_literal: true

require "test_helper"

class GeojsonBusTimedSkipsTest < ActiveSupport::TestCase
  test "tags 823 weekday skip stops and stamps the route note" do
    data = {
      "type" => "FeatureCollection",
      "properties" => { "id" => "new_taipei_823", "ref" => "823", "city_id" => "NewTaipei", "name" => "823" },
      "features" => [
        station("汐止區行政中心(仁愛路)", 0),
        station("秀峰國小", 0),
        station("福安街口", 0),
        station("秀峰高中(忠孝東路)", 1)
      ]
    }

    assert Geojson::BusTimedSkips.annotate!(data)

    tagged = data["features"].select { |feature| feature.dig("properties", "timed_skip") }
    assert_equal [ "汐止區行政中心(仁愛路)", "秀峰國小" ], tagged.map { |feature| feature.dig("properties", "name") }
    assert_equal "weekday", tagged.first.dig("properties", "timed_skip", "days")
    assert_equal [ %w[07:30 08:00], %w[12:00 12:30], %w[16:00 16:30] ],
      tagged.first.dig("properties", "timed_skip", "windows")
    assert_nil data["features"].find { |feature| feature.dig("properties", "name") == "秀峰高中(忠孝東路)" }
      .dig("properties", "timed_skip")
    assert_match(/不停汐止區行政中心/, data.dig("properties", "service_note"))
    assert_match(/no stop at/i, data.dig("properties", "service_note_en"))
    assert_not Geojson::BusTimedSkips.annotate!(data), "idempotent"
  end

  test "ignores routes without a timed-skip rule" do
    data = {
      "type" => "FeatureCollection",
      "properties" => { "id" => "new_taipei_822", "ref" => "822", "city_id" => "NewTaipei" },
      "features" => [ station("秀峰國小", 0) ]
    }

    assert_not Geojson::BusTimedSkips.annotate!(data)
  end

  test "tags 紅7 inbound 陽明戲院 after-11:00 skip" do
    data = {
      "type" => "FeatureCollection",
      "properties" => { "id" => "taipei_hong7", "ref" => "紅7", "city_id" => "Taipei", "name" => "紅7" },
      "features" => [
        station("陽明戲院", 0),
        station("小北街", 1),
        station("陽明戲院", 1),
        station("捷運劍潭站(中山)", 1)
      ]
    }

    assert Geojson::BusTimedSkips.annotate!(data)

    outbound = data["features"].find { |feature|
      feature.dig("properties", "name") == "陽明戲院" && feature.dig("properties", "direction") == 0
    }
    inbound = data["features"].find { |feature|
      feature.dig("properties", "name") == "陽明戲院" && feature.dig("properties", "direction") == 1
    }
    assert_nil outbound.dig("properties", "timed_skip")
    assert_equal "daily", inbound.dig("properties", "timed_skip", "days")
    assert_equal [ %w[11:00 24:00] ], inbound.dig("properties", "timed_skip", "windows")
    assert_match(/不停陽明戲院/, data.dig("properties", "service_note"))
    assert_match(/Yangming Theater/i, data.dig("properties", "service_note_en"))
    assert_not Geojson::BusTimedSkips.annotate!(data), "idempotent"
  end

  test "ensures 紅7區 往劍潭 陽明戲院 and tags the after-11:00 skip" do
    data = {
      "type" => "FeatureCollection",
      "properties" => {
        "id" => "taipei_hong7sh", "ref" => "紅7區", "city_id" => "Taipei",
        "name" => "紅7區", "color" => "#c00"
      },
      "features" => [
        station("小北街", 0),
        station("捷運劍潭站(中山)", 0),
        station("陽明戲院", 1)
      ]
    }

    assert Geojson::BusTimedSkips.annotate!(data)

    names = data["features"].select { |feature|
      feature.dig("properties", "direction") == 0
    }.map { |feature| feature.dig("properties", "name") }
    assert_equal [ "小北街", "陽明戲院", "捷運劍潭站(中山)" ], names

    inbound = data["features"].find { |feature|
      feature.dig("properties", "name") == "陽明戲院" && feature.dig("properties", "direction") == 0
    }
    outbound = data["features"].find { |feature|
      feature.dig("properties", "name") == "陽明戲院" && feature.dig("properties", "direction") == 1
    }
    assert_equal [ 121.5259209, 25.08770498 ], inbound.dig("geometry", "coordinates")
    assert_equal "daily", inbound.dig("properties", "timed_skip", "days")
    assert_equal [ %w[11:00 24:00] ], inbound.dig("properties", "timed_skip", "windows")
    assert_nil outbound.dig("properties", "timed_skip")
    assert_match(/不停陽明戲院/, data.dig("properties", "service_note"))
    assert_not Geojson::BusTimedSkips.annotate!(data), "idempotent"
  end

  test "tags 自來水處(辛亥) peak skips on routes turning from 辛亥 to 基隆" do
    data = {
      "type" => "FeatureCollection",
      "properties" => { "id" => "taipei_673", "ref" => "673", "city_id" => "Taipei", "name" => "673" },
      "features" => [
        station("青峰活動中心", 0),
        station("自來水處(辛亥)", 0),
        station("基隆長興街口", 0),
        station("自來水處(辛亥)", 1)
      ]
    }

    assert Geojson::BusTimedSkips.annotate!(data)

    tagged = data["features"].select { |feature| feature.dig("properties", "timed_skip") }
    assert_equal 2, tagged.size
    assert_equal "daily", tagged.first.dig("properties", "timed_skip", "days")
    assert_equal [ %w[07:00 09:00], %w[17:00 19:00] ], tagged.first.dig("properties", "timed_skip", "windows")
    assert_match(/不停自來水處/, data.dig("properties", "service_note"))
  end

  test "tags 939 outbound morning 萬坪 skip and holiday 市政府(市府) skip" do
    data = {
      "type" => "FeatureCollection",
      "properties" => { "id" => "new_taipei_939", "ref" => "939", "city_id" => "NewTaipei", "name" => "939" },
      "features" => [
        station("上善若水社區", 0),
        station("景觀萬坪公園(公厝仔)", 0),
        station("敦化和平路口", 0),
        station("市政府(市府)", 0),
        station("市政府(松高)", 0),
        station("景觀萬坪公園(公厝仔)", 1),
        station("市政府(市府)", 1)
      ]
    }

    assert Geojson::BusTimedSkips.annotate!(data)

    wanping = data["features"].find { |feature|
      feature.dig("properties", "name") == "景觀萬坪公園(公厝仔)" && feature.dig("properties", "direction") == 0
    }
    city_hall = data["features"].find { |feature|
      feature.dig("properties", "name") == "市政府(市府)" && feature.dig("properties", "direction") == 0
    }
    assert_equal "weekday", wanping.dig("properties", "timed_skip", "days")
    assert_equal [ %w[06:00 09:00] ], wanping.dig("properties", "timed_skip", "windows")
    assert_equal "holiday", city_hall.dig("properties", "timed_skip", "days")
    assert_equal [], city_hall.dig("properties", "timed_skip", "windows")
    assert_nil data["features"].find { |feature|
      feature.dig("properties", "name") == "景觀萬坪公園(公厝仔)" && feature.dig("properties", "direction") == 1
    }.dig("properties", "timed_skip")
    assert_nil data["features"].find { |feature|
      feature.dig("properties", "name") == "市政府(市府)" && feature.dig("properties", "direction") == 1
    }.dig("properties", "timed_skip")
    assert_match(/往程不停景觀萬坪公園/, data.dig("properties", "service_note"))
    assert_match(/假日改走逸仙路/, data.dig("properties", "service_note"))
    assert_match(/Yixian/i, data.dig("properties", "service_note_en"))
  end

  def station(name, direction)
    {
      "type" => "Feature",
      "properties" => { "feature_type" => "station", "name" => name, "direction" => direction, "ref" => "NWT#{name.bytes.sum}" },
      "geometry" => { "type" => "Point", "coordinates" => [ 121.65, 25.07 ] }
    }
  end
end
