# frozen_string_literal: true

require "test_helper"

class MetroLineBuilderHsrTest < ActiveSupport::TestCase
  test "taiwan hsr geojson spans west coast with twelve stations" do
    path = Rails.root.join("public/geojson/hsr/taiwan_hsr.geojson")
    skip "run bin/rails geojson:hsr first" unless path.exist?

    data = JSON.parse(path.read)
    routes = data["features"].select { |feature| feature.dig("properties", "feature_type") == "route" }
    stations = data["features"].select { |feature| feature.dig("properties", "feature_type") == "station" }

    assert_equal 1, routes.length, "expected one merged HSR track"
    assert_equal 12, stations.length

    route = routes.first
    first_coord = route.dig("geometry", "coordinates", 0)
    assert first_coord[0].between?(120.0, 122.0)
    assert first_coord[1].between?(22.0, 25.5)

    assert_equal "01;980;BL22", stations.find { |f| f.dig("properties", "name") == "南港" }.dig("properties", "ref")
    assert_equal "12;4340;R16", stations.find { |f| f.dig("properties", "name") == "左營" }.dig("properties", "ref")
    refute stations.any? { |feature| feature.dig("properties", "station_role").present? }

    banqiao = stations.find { |f| f.dig("properties", "name") == "板橋" }
    lon, lat = banqiao.dig("geometry", "coordinates")
    expected = Geojson::HsrCatalog::FALLBACK_STATIONS.find { |s| s[:name] == "板橋" }

    assert_in_delta expected[:lon], lon, 0.002
    assert_in_delta expected[:lat], lat, 0.002

    hsinchu = stations.find { |f| f.dig("properties", "name") == "新竹" }
    hub = Geojson::TransitTransferCatalog::HSINCHU_HSR_HUB
    hlon, hlat = hsinchu.dig("geometry", "coordinates")

    assert_equal "05;1194", hsinchu.dig("properties", "ref")
    assert_in_delta hub[:lon], hlon, 0.002, "新竹 longitude"
    assert_in_delta hub[:lat], hlat, 0.002, "新竹 latitude"
    refute_in_delta 120.971683, hlon, 0.01, "新竹 should not use downtown TRA coordinates"

    miaoli = stations.find { |f| f.dig("properties", "name") == "苗栗" }
    expected_miaoli = Geojson::HsrCatalog::FALLBACK_STATIONS.find { |s| s[:name] == "苗栗" }
    mlon, mlat = miaoli.dig("geometry", "coordinates")

    assert_in_delta expected_miaoli[:lon], mlon, 0.002, "苗栗 longitude"
    assert_in_delta expected_miaoli[:lat], mlat, 0.002, "苗栗 latitude"

    assert_equal Geojson::HsrCatalog::BRAND_COLOR, routes.first.dig("properties", "color")
  end

  test "fetch hsr stations uses catalog fallbacks exclusively" do
    builder = Geojson::MetroLineBuilder.new(Geojson::HsrCatalog::LINES.first)
    stations = builder.send(:fetch_hsr_stations)

    assert_equal 12, stations.length
    assert_equal Geojson::HsrCatalog::FALLBACK_STATIONS.map { |station| station[:ref] },
                 stations.map { |station| station[:ref] }

    hsinchu = stations.find { |station| station[:name] == "新竹" }
    miaoli = stations.find { |station| station[:name] == "苗栗" }

    assert_equal "05", hsinchu[:ref]
    assert_equal "06", miaoli[:ref]
    assert hsinchu[:lat] > miaoli[:lat], "新竹 should be north of 苗栗"
    assert hsinchu[:lon] > miaoli[:lon], "新竹 should be east of 苗栗"
  end

  test "hsr station names map to ordered refs" do
    builder = Geojson::MetroLineBuilder.new(Geojson::HsrCatalog::LINES.first)

    assert_equal "07", builder.send(:hsr_ref_for_station_name, "高鐵台中站")
    assert_equal "04", builder.send(:hsr_ref_for_station_name, "桃園")
  end
end
