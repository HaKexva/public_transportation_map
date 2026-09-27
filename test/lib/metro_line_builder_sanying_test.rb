# frozen_string_literal: true

require "test_helper"

class MetroLineBuilderSanyingTest < ActiveSupport::TestCase
  test "sanying depot spur follows yard approach and ends at facility body" do
    path = Rails.root.join("public/geojson/new_taipei_metro/sanying_line.geojson")
    skip "rebuild sanying_line.geojson first" unless path.exist?

    data = JSON.parse(path.read)
    spur = data.fetch("features").find { |feature| feature.dig("properties", "depot_id") == "sanying_depot" }
    assert spur, "expected 三峽機廠支線"

    coords = spur.dig("geometry", "coordinates")
    assert_operator coords.length, :>=, 10
    assert_operator Geojson::TrackGeometry.path_length_meters(coords), :>, 400

    # Must not end at the old west-of-landuse stub.
    refute_in_delta 121.3805, coords.last[0], 0.0005

    assert_in_delta 121.38319, coords.last[0], 0.001
    assert_in_delta 24.93397, coords.last[1], 0.001
    assert_operator coords.first[1], :>, coords.last[1], "spur should run south into the yard"

    depot = Geojson::MetroDepotCatalog::DEPOTS.find { |entry| entry[:id] == "sanying_depot" }
    assert_in_delta 121.38319, depot[:lon], 0.00001
    assert_in_delta 24.93397, depot[:lat], 0.00001
  end
end
