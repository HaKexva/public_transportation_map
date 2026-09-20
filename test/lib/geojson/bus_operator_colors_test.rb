# frozen_string_literal: true

require "test_helper"

class GeojsonBusOperatorColorsTest < ActiveSupport::TestCase
  test "maps known Taipei operators to brand colors" do
    assert_equal "#7CB342", Geojson::BusOperatorColors.for_route(name: "大都會客運")
    assert_equal "#F97316", Geojson::BusOperatorColors.for_route(name: "首都客運")
    assert_equal "#F97316", Geojson::BusOperatorColors.for_route(name: "臺北客運")
    assert_equal "#EAB308", Geojson::BusOperatorColors.for_route(name: "大南汽車")
    assert_equal "#16A34A", Geojson::BusOperatorColors.for_route(name: "三重客運")
  end

  test "maps zhongxing group operators to the same red" do
    %w[中興巴士 光華巴士 淡水客運 指南客運].each do |name|
      assert_equal "#DC2626", Geojson::BusOperatorColors.for_route(name: name), name
    end
  end

  test "F-prefix refs use 新巴士 blue-green-gray" do
    assert_equal "#6B8F9A", Geojson::BusOperatorColors.for_route(ref: "F123", name: "淡水區公所")
    assert_equal "#6B8F9A", Geojson::BusOperatorColors.for_route(ref: "F101樹興")
    assert_equal "#6B8F9A", Geojson::BusOperatorColors.for_route(ref: "f126")
  end

  test "新北客運 without F-prefix is not auto-branded as 新巴士" do
    assert_nil Geojson::BusOperatorColors.for_route(ref: "817", name: "新北客運")
  end

  test "does not brand-match district offices without F ref" do
    assert_nil Geojson::BusOperatorColors.for_route(ref: "L312", name: "淡水區公所")
    assert_nil Geojson::BusOperatorColors.for_route(name: "新店區公所")
  end

  test "apply_to_geojson updates collection and feature colors" do
    data = {
      "properties" => { "ref" => "綠2", "operator" => "大南汽車", "color" => "#9a3412" },
      "features" => [
        { "properties" => { "feature_type" => "route", "color" => "#9a3412" } },
        { "properties" => { "feature_type" => "station", "color" => "#9a3412" } }
      ]
    }

    assert Geojson::BusOperatorColors.apply_to_geojson!(data)
    assert_equal "#EAB308", data.dig("properties", "color")
    assert_equal "#EAB308", data.dig("features", 0, "properties", "color")
  end
end
