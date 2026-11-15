# frozen_string_literal: true

require "test_helper"

class Transit::ItineraryGeocoderTest < ActiveSupport::TestCase
  test "search parses county district and village into admin" do
    payload = {
      "status" => "OK",
      "results" => [
        {
          "place_id" => "ChIJvillage",
          "formatted_address" => "100台灣臺北市中正區東門里凱達格蘭大道1號",
          "geometry" => { "location" => { "lat" => 25.04, "lng" => 121.52 } },
          "address_components" => [
            { "long_name" => "1號", "types" => [ "street_number" ] },
            { "long_name" => "凱達格蘭大道", "types" => [ "route" ] },
            { "long_name" => "東門里", "types" => [ "administrative_area_level_4", "political" ] },
            { "long_name" => "中正區", "types" => [ "administrative_area_level_3", "political" ] },
            { "long_name" => "臺北市", "types" => [ "administrative_area_level_1", "political" ] },
            { "long_name" => "台灣", "types" => [ "country", "political" ] }
          ],
          "types" => [ "street_address" ]
        }
      ]
    }
    stub_geocode(payload) do
      places = Transit::Itinerary::Geocoder.search("總統府", api_key: "test-key")

      assert_equal 1, places.length
      assert_equal "凱達格蘭大道1號", places.first["name"]
      assert_equal "臺北市中正區東門里", places.first["admin"]
      assert_equal "place", places.first["kind"]
      assert_in_delta 25.04, places.first["lat"], 0.0001
      assert_in_delta 121.52, places.first["lon"], 0.0001
    end
  end

  test "search keeps landmark name when address is only the place" do
    payload = {
      "status" => "OK",
      "results" => [
        {
          "place_id" => "ChIJ101",
          "formatted_address" => "台北101",
          "geometry" => { "location" => { "lat" => 25.034, "lng" => 121.5645 } },
          "address_components" => [
            { "long_name" => "信義區", "types" => [ "administrative_area_level_3", "political" ] },
            { "long_name" => "臺北市", "types" => [ "administrative_area_level_1", "political" ] },
            { "long_name" => "台灣", "types" => [ "country", "political" ] }
          ],
          "types" => [ "premise", "point_of_interest", "establishment" ]
        }
      ]
    }
    stub_geocode(payload) do
      place = Transit::Itinerary::Geocoder.search("台北101", api_key: "test-key").first

      assert_equal "台北101", place["name"]
      assert_equal "臺北市信義區", place["admin"]
    end
  end

  test "lookup returns the first hit for itinerary callers" do
    payload = {
      "status" => "OK",
      "results" => [
        {
          "formatted_address" => "板橋車站",
          "geometry" => { "location" => { "lat" => 25.01, "lng" => 121.46 } },
          "address_components" => [
            { "long_name" => "板橋區", "types" => [ "administrative_area_level_3", "political" ] },
            { "long_name" => "新北市", "types" => [ "administrative_area_level_1", "political" ] }
          ],
          "types" => [ "premise" ]
        }
      ]
    }
    stub_geocode(payload) do
      found = Transit::Itinerary::Geocoder.lookup("板橋車站", api_key: "test-key")

      assert_equal "板橋車站", found["name"]
      assert_in_delta 25.01, found["lat"], 0.0001
      assert_nil found["admin"]
    end
  end

  test "search returns empty without an api key" do
    assert_equal [], Transit::Itinerary::Geocoder.search("台北101", api_key: nil)
  end

  private

  def stub_geocode(payload)
    original = Net::HTTP.method(:get)
    Net::HTTP.define_singleton_method(:get) { |_uri| JSON.generate(payload) }
    yield
  ensure
    Net::HTTP.define_singleton_method(:get, original)
  end
end
