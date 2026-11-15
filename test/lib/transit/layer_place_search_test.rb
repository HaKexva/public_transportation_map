# frozen_string_literal: true

require "test_helper"

class TransitLayerPlaceSearchTest < ActiveSupport::TestCase
  setup do
    @root = Rails.root.join("tmp/layer_place_search_#{SecureRandom.hex(4)}")
    FileUtils.mkdir_p(@root.join("keelung_bus"))
    File.write(@root.join("keelung_bus/_stop_routes.json"), JSON.generate(
      "groups" => {
        "KEE1" => {
          "name" => "基隆車站",
          "name_en" => "Keelung Station",
          "lat" => 25.1318,
          "lon" => 121.7394,
          "road" => "忠一路",
          "toward" => "海洋廣場",
          "stops" => [ "KEE100" ]
        }
      }
    ))
    Geojson::BusStopSearchIndex.write!(bus_root: @root)
    Transit::BusStopSearch.reset_cache!
  end

  teardown do
    Transit::BusStopSearch.reset_cache!
    FileUtils.rm_rf(@root)
  end

  test "returns stops and google places when geocoder is available" do
    geocoder = lambda do |_query, limit:|
      [
        {
          "name" => "海洋廣場",
          "lat" => 25.128,
          "lon" => 121.742,
          "admin" => "基隆市仁愛區",
          "kind" => "place",
          "place_id" => "ChIJplaza"
        }
      ].first(limit)
    end

    result = Transit::LayerPlaceSearch.new(
      query: "基隆車站",
      bus_root: @root,
      geocoder:,
      configured: true
    ).call

    assert_equal [ "基隆車站" ], result[:stops].map { |stop| stop["name"] }
    assert_equal 1, result[:places].length
    place = result[:places].first
    assert_equal "海洋廣場", place["name"]
    assert_equal "基隆市仁愛區", place["city"]
    assert_equal "place", place["kind"]
  end

  test "drops google hits that duplicate a nearby stop name" do
    geocoder = lambda do |_query, limit:|
      [
        {
          "name" => "基隆車站",
          "lat" => 25.1318,
          "lon" => 121.7394,
          "admin" => "基隆市仁愛區",
          "kind" => "place"
        }
      ].first(limit)
    end

    result = Transit::LayerPlaceSearch.new(
      query: "基隆車站",
      bus_root: @root,
      geocoder:,
      configured: true
    ).call

    assert_equal [ "基隆車站" ], result[:stops].map { |stop| stop["name"] }
    assert_equal [], result[:places]
  end

  test "returns empty places when google maps is not configured" do
    result = Transit::LayerPlaceSearch.new(
      query: "基隆車站",
      bus_root: @root,
      geocoder: ->(*) { raise "should not call geocoder" },
      configured: false
    ).call

    assert_equal [ "基隆車站" ], result[:stops].map { |stop| stop["name"] }
    assert_equal [], result[:places]
  end
end
