# frozen_string_literal: true

require "test_helper"

class ApiItinerariesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @graph = Transit::Itinerary::Compiler.build(patterns: [ {
      id: "blue",
      name: "測試捷運",
      mode: "metro",
      stops: [
        { key: "a", name: "規劃起站", lat: 25.05, lon: 121.50, kind: "metro" },
        { key: "b", name: "規劃迄站", lat: 25.08, lon: 121.50, kind: "metro" }
      ],
      services: { "daily" => { trips: [ [ 8 * 60, 8 * 60 + 12 ] ], headways: [] } }
    } ])
    Transit::Itinerary::Graph.override = @graph
  end

  teardown do
    Transit::Itinerary::Graph.clear_override!
    Transit::Itinerary::PlaceResolver.geocoder = nil
  end

  test "plans between two named stops" do
    post api_itineraries_url, params: {
      origin: { query: "規劃起站" },
      destination: { query: "規劃迄站" },
      depart_at: "2026-10-26T07:50"
    }, as: :json

    assert_response :success
    body = JSON.parse(response.body)
    ride = body["itineraries"].first["legs"].find { |leg| leg["kind"] == "ride" }
    assert_equal "測試捷運", ride["name"]
    assert ride["geometry"].length >= 2
  end

  test "geocodes an address when no stop matches" do
    Transit::Itinerary::PlaceResolver.geocoder = lambda do |query|
      { "lat" => 25.05, "lon" => 121.50, "name" => query }
    end

    post api_itineraries_url, params: {
      origin: { query: "台北市某地址 100 號" },
      destination: { lat: 25.08, lon: 121.50, name: "規劃迄站" },
      depart_at: "2026-10-26T07:50"
    }, as: :json

    assert_response :success
    assert JSON.parse(response.body)["itineraries"].any?
  end

  test "returns an error when a place cannot be resolved" do
    post api_itineraries_url, params: {
      origin: { query: "不存在的地址zzzz" },
      destination: { query: "規劃迄站" },
      depart_at: "2026-10-26T07:50"
    }, as: :json

    assert_response :unprocessable_entity
    assert_equal "place_not_found", JSON.parse(response.body)["error"]
  end

  test "lists matching places" do
    get places_api_itineraries_url, params: { q: "規劃起" }

    assert_response :success
    places = JSON.parse(response.body)["places"]
    assert_equal [ "規劃起站" ], places.map { |place| place["name"] }
    assert_equal [ "規劃起站（捷運）" ], places.map { |place| place["label"] }
    assert_equal [ "捷運" ], places.map { |place| place["detail"] }
  end
end
