# frozen_string_literal: true

require "test_helper"

class GeojsonBusDepotGeocoderTest < ActiveSupport::TestCase
  setup do
    @root = Rails.root.join("tmp/bus_depot_geocoder_test_#{SecureRandom.hex(4)}")
    FileUtils.mkdir_p(@root)
    @manual = @root.join("manual.md")
  end

  teardown do
    FileUtils.rm_rf(@root)
  end

  test "fills blank coordinates of hand-added depots from the address note" do
    depot_rows = [
      { "city" => "taipei_new_taipei_bus", "code" => "S1", "name" => "自動", "lon" => "121.1", "lat" => "25.1", "note" => "自動偵測" },
      { "city" => "taipei_new_taipei_bus", "code" => "N1", "name" => "林口站", "note" => "新北市林口區文化北路一段568號（與臺北客運共用場地）" },
      { "city" => "taipei_new_taipei_bus", "code" => "N2", "name" => "關渡站", "note" => "臺北市北投區關渡路口" },
      { "city" => "taipei_new_taipei_bus", "code" => "N3", "name" => "不明站", "note" => "查無此址" }
    ]
    route_rows = [ { "city" => "taipei_new_taipei_bus", "route_id" => "r1", "route_name" => "1", "depot_code" => "N1" } ]
    File.write(@manual, Geojson::BusDepotWriter.manual_markdown(depot_rows:, route_rows:))

    queried = []
    lookup = lambda do |address|
      queried << address
      case address
      when "新北市林口區文化北路一段568號" then { lon: 121.3891234567, lat: 25.0712, approximate: false }
      when "臺北市北投區關渡路口" then { lon: 121.47, lat: 25.12, approximate: true }
      end
    end

    result = Geojson::BusDepotGeocoder.call(manual_path: @manual, api_key: "x", lookup:)
    assert_equal %w[N1 N2], result.filled
    assert_equal %w[N3], result.failed
    assert_equal [ "新北市林口區文化北路一段568號", "臺北市北投區關渡路口", "查無此址" ], queried

    parsed = Geojson::BusDepotWriter.parse_manual(@manual)
    depots = parsed.depots.index_by { |row| row["code"] }
    assert_equal [ "121.389123", "25.0712" ], depots["N1"].values_at("lon", "lat")
    assert_equal "臺北市北投區關渡路口・座標約略，請確認", depots["N2"]["note"]
    assert_equal "", depots["N3"]["lon"]
    assert_equal [ "N1" ], parsed.routes.map { |row| row["depot_code"] }
  end
end
