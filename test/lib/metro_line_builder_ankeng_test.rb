# frozen_string_literal: true

require "test_helper"

class MetroLineBuilderAnkengTest < ActiveSupport::TestCase
  test "ankeng passenger tip leaves depot yard and spur reaches facility body" do
    path = Rails.root.join("public/geojson/new_taipei_metro/ankeng_lrt.geojson")
    skip "rebuild ankeng_lrt.geojson first" unless path.exist?

    data = JSON.parse(path.read)
    route = data.fetch("features").find { |feature| feature.dig("properties", "feature_type") == "route" }
    spur = data.fetch("features").find { |feature| feature.dig("properties", "depot_id") == "ankeng_depot" }
    assert route
    assert spur, "expected 安坑機廠支線"

    coords = route.dig("geometry", "coordinates")
    tip = coords.first
    refute coords.any? { |lon, lat| lat < 24.9432 && lon < 121.4875 },
           "passenger route should not include the deep yard nose"

    assert_in_delta 121.4878174, tip[0], 0.0005
    assert_in_delta 24.9434738, tip[1], 0.0005

    spur_coords = spur.dig("geometry", "coordinates")
    assert_operator Geojson::TrackGeometry.path_length_meters(spur_coords), :>, 250
    assert_in_delta 121.48660, spur_coords.last[0], 0.0008
    assert_in_delta 24.94466, spur_coords.last[1], 0.0008

    depot = Geojson::MetroDepotCatalog::DEPOTS.find { |entry| entry[:id] == "ankeng_depot" }
    assert_in_delta 121.48660, depot[:lon], 0.00001
    assert_in_delta 24.94466, depot[:lat], 0.00001
  end
end
