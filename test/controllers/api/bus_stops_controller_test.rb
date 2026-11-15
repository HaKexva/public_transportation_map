# frozen_string_literal: true

require "test_helper"

class ApiBusStopsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @root = Rails.root.join("tmp/bus_stops_api_#{SecureRandom.hex(4)}")
    FileUtils.mkdir_p(@root.join("keelung_bus"))
    File.write(@root.join("keelung_bus/_stop_routes.json"), JSON.generate(
      "groups" => {
        "KEE1" => {
          "name" => "基隆車站",
          "lat" => 25.13,
          "lon" => 121.74,
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

  test "index returns matching stops" do
    Geojson::BusLayout.with_bus_root(@root) do
      without_google_places do
        get api_bus_stops_url, params: { q: "基隆車站" }
      end
    end

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal [ "基隆車站" ], body["stops"].map { |stop| stop["name"] }
    assert_equal "Keelung", body["stops"].first["city_id"]
    assert_equal [], body["places"]
  end

  test "index includes google places when geocoding is available" do
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

    Geojson::BusLayout.with_bus_root(@root) do
      with_google_places(geocoder) do
        get api_bus_stops_url, params: { q: "基隆車站" }
      end
    end

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal [ "基隆車站" ], body["stops"].map { |stop| stop["name"] }
    assert_equal "海洋廣場", body["places"].first["name"]
    assert_equal "基隆市仁愛區", body["places"].first["city"]
    assert_equal "place", body["places"].first["kind"]
  end

  test "index returns nothing for a one character query" do
    Geojson::BusLayout.with_bus_root(@root) do
      get api_bus_stops_url, params: { q: "站" }
    end

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal [], body["stops"]
    assert_equal [], body["places"]
  end

  private

  def without_google_places(&block)
    wrap_layer_place_search(configured: false, &block)
  end

  def with_google_places(geocoder, &block)
    wrap_layer_place_search(configured: true, geocoder:, &block)
  end

  def wrap_layer_place_search(configured:, geocoder: nil)
    original_new = Transit::LayerPlaceSearch.method(:new)
    Transit::LayerPlaceSearch.define_singleton_method(:new) do |**kwargs|
      original_new.call(**kwargs, geocoder: geocoder || kwargs[:geocoder], configured:)
    end
    yield
  ensure
    Transit::LayerPlaceSearch.define_singleton_method(:new, original_new)
  end
end
