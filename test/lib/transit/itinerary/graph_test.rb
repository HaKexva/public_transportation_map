# frozen_string_literal: true

require "test_helper"

class Transit::ItineraryGraphTest < ActiveSupport::TestCase
  test "prefers metro over bus when both share an exact station name" do
    graph = Transit::Itinerary::Graph.new(
      "stops" => [
        { "name" => "西門", "name_en" => "Ximen", "lat" => 23.96, "lon" => 120.48, "kind" => "bus", "key" => "bus:1" },
        { "name" => "西門", "name_en" => "", "lat" => 25.04, "lon" => 121.51, "kind" => "metro", "key" => "metro:1" },
        { "name" => "西門口", "name_en" => "", "lat" => 24.8, "lon" => 120.96, "kind" => "bus", "key" => "bus:2" }
      ],
      "routes" => [],
      "transfers" => []
    )

    places = graph.search_stops("西門", limit: 3)

    assert_equal "metro", places.first["kind"]
    assert_in_delta 25.04, places.first["lat"], 0.001
    assert places.any? { |place| place["kind"] == "bus" }
  end
end
