# frozen_string_literal: true

require "test_helper"

class MetroLineBuilderMaokongTest < ActiveSupport::TestCase
  test "maokong gondola geojson lists six stops in order from zoo to maokong" do
    path = Rails.root.join("public/geojson/other/maokong_gondola.geojson")
    skip "run bin/rails geojson:other first" unless path.exist?

    data = JSON.parse(path.read)
    stops = data["features"].select do |feature|
      %w[station angle_station].include?(feature.dig("properties", "feature_type"))
    end

    assert_equal 6, stops.length

    ordered = stops.sort_by { |feature| feature.dig("properties", "ref").to_s }
    assert_equal %w[G1;BR01 G2 G3 G4 G5 G6], ordered.map { |feature| feature.dig("properties", "ref") }
    assert_equal [ "動物園", "轉角一", "動物園南", "轉角二", "指南宮", "貓空" ],
                 ordered.map { |feature| feature.dig("properties", "name") }
  end

  test "maokong gondola geojson includes two angle stations without passenger service" do
    path = Rails.root.join("public/geojson/other/maokong_gondola.geojson")
    skip "run bin/rails geojson:other first" unless path.exist?

    data = JSON.parse(path.read)
    angles = data["features"].select { |f| f.dig("properties", "feature_type") == "angle_station" }

    assert_equal 2, angles.length
    names = angles.map { |f| f.dig("properties", "name") }.sort
    assert_equal %w[轉角一 轉角二], names
    angles.each do |feature|
      assert_equal false, feature.dig("properties", "passenger_service")
      assert_includes feature.dig("properties", "note"), "不提供載客服務"
    end
  end
end

class MetroLineBuilderSkytrainTest < ActiveSupport::TestCase
  test "skytrain geojson has separate north and south boarding stations" do
    path = Rails.root.join("public/geojson/other/taoyuan_airport_skytrain.geojson")
    skip "run bin/rails geojson:other first" unless path.exist?

    data = JSON.parse(path.read)
    stations = data["features"].select { |feature| feature.dig("properties", "feature_type") == "station" }

    assert_equal 4, stations.length

    by_ref = stations.index_by { |feature| feature.dig("properties", "ref") }
    assert_equal "第一航廈（北側）", by_ref["ST1N"].dig("properties", "name")
    assert_equal "第二航廈（北側）", by_ref["ST2N"].dig("properties", "name")
    assert_equal "第一航廈（南側）", by_ref["ST1S"].dig("properties", "name")
    assert_equal "第二航廈（南側）", by_ref["ST2S"].dig("properties", "name")

    assert_equal "secured", by_ref["ST1N"].dig("properties", "boarding_area")
    assert_equal "secured", by_ref["ST2N"].dig("properties", "boarding_area")
    assert_equal "public", by_ref["ST1S"].dig("properties", "boarding_area")
    assert_equal "public", by_ref["ST2S"].dig("properties", "boarding_area")

    refute_equal false, by_ref["ST1N"].dig("properties", "passenger_service")
    refute_equal false, by_ref["ST2N"].dig("properties", "passenger_service")
    assert_equal false, by_ref["ST1S"].dig("properties", "passenger_service")
    assert_equal false, by_ref["ST2S"].dig("properties", "passenger_service")
    assert_includes by_ref["ST1S"].dig("properties", "note"), "停駛"
    assert_includes by_ref["ST2S"].dig("properties", "note"), "停駛"
    assert_not_includes by_ref.keys, "ST01"
  end

  test "skytrain route segments distinguish north secured and south public tracks" do
    path = Rails.root.join("public/geojson/other/taoyuan_airport_skytrain.geojson")
    skip "run bin/rails geojson:other first" unless path.exist?

    data = JSON.parse(path.read)
    routes = data["features"].select { |feature| feature.dig("properties", "feature_type") == "route" }

    segments = routes.map { |feature| feature.dig("properties", "segment") }.uniq.sort
    assert_equal %w[north south], segments

    north_names = routes.select { |r| r.dig("properties", "segment") == "north" }.map { |r| r.dig("properties", "name") }
    south_names = routes.select { |r| r.dig("properties", "segment") == "south" }.map { |r| r.dig("properties", "name") }

    assert north_names.all? { |name| name.include?("北側") && name.include?("管制區內") }
    assert south_names.all? { |name| name.include?("南側") && name.include?("管制區外") }
  end
end
