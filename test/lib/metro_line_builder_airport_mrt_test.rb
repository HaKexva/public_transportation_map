# frozen_string_literal: true

require "test_helper"

class MetroLineBuilderAirportMrtTest < ActiveSupport::TestCase
  test "airport mrt commuter route reaches A1 taipei main station without stub backtrack" do
    path = Rails.root.join("public/geojson/taoyuan_metro/airport_mrt.geojson")
    data = JSON.parse(path.read)

    route = data.fetch("features").find { |feature| feature.dig("properties", "feature_type") == "route" }
    a1 = data.fetch("features").find { |feature| feature.dig("properties", "ref").to_s.split(";").include?("A1") }
    assert route
    assert a1

    coordinates = route.dig("geometry", "coordinates")
    a1_coords = a1.dig("geometry", "coordinates")

    assert_in_delta a1_coords[0], coordinates.first[0], 0.000001
    assert_in_delta a1_coords[1], coordinates.first[1], 0.000001

    # No out-and-back: after leaving A1, path should not return within 5m for the next 300m.
    returned = false
    traveled = 0.0
    coordinates.each_cons(2).with_index do |(start, finish), index|
      next if index.zero?

      traveled += Geojson::TrackGeometry.planar_distance_meters(start[0], start[1], finish[0], finish[1])
      break if traveled > 300

      if Geojson::TrackGeometry.planar_distance_meters(a1_coords[0], a1_coords[1], finish[0], finish[1]) < 5
        returned = true
        break
      end
    end
    refute returned, "expected no A1 stub out-and-back on the airport MRT track"
  end
end
