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

    refs = stations.map { |feature| feature.dig("properties", "ref") }.sort
    assert_equal Geojson::HsrCatalog::FALLBACK_STATIONS.map { |station| station[:ref] }.sort, refs

    assert_equal "01", stations.find { |f| f.dig("properties", "name") == "南港" }.dig("properties", "ref")
    assert_equal "12", stations.find { |f| f.dig("properties", "name") == "左營" }.dig("properties", "ref")
    refute stations.any? { |feature| feature.dig("properties", "station_role").present? }

    banqiao = stations.find { |f| f.dig("properties", "name") == "板橋" }
    lon, lat = banqiao.dig("geometry", "coordinates")
    expected = Geojson::HsrCatalog::FALLBACK_STATIONS.find { |s| s[:name] == "板橋" }

    assert_in_delta expected[:lon], lon, 0.002
    assert_in_delta expected[:lat], lat, 0.002

    %w[新竹 苗栗].each do |name|
      station = stations.find { |f| f.dig("properties", "name") == name }
      expected_station = Geojson::HsrCatalog::FALLBACK_STATIONS.find { |s| s[:name] == name }
      slon, slat = station.dig("geometry", "coordinates")

      assert_in_delta expected_station[:lon], slon, 0.002, "#{name} longitude"
      assert_in_delta expected_station[:lat], slat, 0.002, "#{name} latitude"
    end

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
