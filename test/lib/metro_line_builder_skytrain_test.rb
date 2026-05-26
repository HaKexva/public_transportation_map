# frozen_string_literal: true

require "test_helper"

class MetroLineBuilderMaokongTest < ActiveSupport::TestCase
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
  test "skytrain geojson uses terminal refs ST01 and ST02" do
    path = Rails.root.join("public/geojson/other/taoyuan_airport_skytrain.geojson")
    skip "run bin/rails geojson:other first" unless path.exist?

    data = JSON.parse(path.read)
    stations = data["features"].select { |feature| feature.dig("properties", "feature_type") == "station" }

    assert_equal 2, stations.length

    by_ref = stations.to_h { |feature| [ feature.dig("properties", "ref"), feature.dig("properties", "name") ] }
    assert_equal "第一航廈", by_ref["ST01"]
    assert_equal "第二航廈", by_ref["ST02"]
    assert_not_includes by_ref.keys, "Skytrain"
  end

  test "skytrain route segments are labeled outbound and inbound" do
    path = Rails.root.join("public/geojson/other/taoyuan_airport_skytrain.geojson")
    skip "run bin/rails geojson:other first" unless path.exist?

    data = JSON.parse(path.read)
    route_names = data["features"]
      .select { |feature| feature.dig("properties", "feature_type") == "route" }
      .map { |feature| feature.dig("properties", "name") }

    assert route_names.any? { |name| name.include?("往程") }
    assert route_names.any? { |name| name.include?("返程") }
  end
end
