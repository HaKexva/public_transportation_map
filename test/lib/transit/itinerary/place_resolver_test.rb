# frozen_string_literal: true

require "test_helper"

class Transit::ItineraryPlaceResolverTest < ActiveSupport::TestCase
  setup do
    @graph = Transit::Itinerary::Graph.new(
      "stops" => [
        { "name" => "臺中", "name_en" => "", "lat" => 24.137, "lon" => 120.687, "kind" => "rail", "key" => "rail:1" },
        { "name" => "台中", "name_en" => "", "lat" => 24.110, "lon" => 120.616, "kind" => "hsr", "key" => "hsr:1" },
        { "name" => "板橋", "name_en" => "", "lat" => 25.014, "lon" => 121.464, "kind" => "metro", "key" => "metro:1" }
      ],
      "routes" => [],
      "transfers" => []
    )
  end

  test "labels TRA and HSR when the city names only differ by 臺/台" do
    places = Transit::Itinerary::PlaceResolver.search("台中", graph: @graph, limit: 4)

    rail = places.find { |place| place["kind"] == "rail" }
    hsr = places.find { |place| place["kind"] == "hsr" }

    assert_equal "臺中", rail["name"]
    assert_equal "臺中（台鐵）", rail["label"]
    assert_equal "台鐵", rail["detail"]
    assert_equal "台中", hsr["name"]
    assert_equal "台中（高鐵）", hsr["label"]
    assert_equal "高鐵", hsr["detail"]
  end

  test "labels metro stops that share a short city name" do
    place = Transit::Itinerary::PlaceResolver.search("板橋", graph: @graph, limit: 1).first

    assert_equal "板橋（捷運）", place["label"]
    assert_equal "捷運", place["detail"]
  end
end
