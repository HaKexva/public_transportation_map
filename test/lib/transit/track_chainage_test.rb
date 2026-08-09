# frozen_string_literal: true

require "test_helper"

class TrackChainageTest < ActiveSupport::TestCase
  setup do
    @fixture = Rails.root.join("test/fixtures/files/geojson/test_chainage.geojson")
    @public_copy = Rails.root.join("public/geojson/test_chainage.geojson")
    FileUtils.mkdir_p(@public_copy.dirname)
    FileUtils.cp(@fixture, @public_copy)

    @route = TransitRoute.create!(
      system_id: "tra",
      route_id: "test_chainage_line",
      name: "測試里程線",
      line_ref: "TK",
      geojson_path: "/geojson/test_chainage.geojson"
    )
  end

  teardown do
    @public_copy.delete if @public_copy.exist?
    Transit::GeojsonStationCoords.clear_cache!
  end

  test "builds cumulative kilometers and interpolates a midpoint" do
    chainage = Transit::TrackChainage.for_route(@route)
    assert chainage
    assert chainage[:length_km] > 2.0

    start = Transit::TrackChainage.point_at(chainage, 0)
    assert_in_delta 25.0, start[:lat], 0.0001
    assert_in_delta 121.0, start[:lng], 0.0001

    mid = Transit::TrackChainage.point_at(chainage, chainage[:length_km] / 2.0)
    assert_in_delta 25.0, mid[:lat], 0.001
    assert mid[:lng] > 121.01
    assert mid[:lng] < 121.02
  end

  test "snaps a nearby point back onto the chainage" do
    chainage = Transit::TrackChainage.for_route(@route)
    dist = Transit::TrackChainage.nearest_distance(chainage, 121.0100, 25.0002)
    assert dist
    assert dist > 0.8
    assert dist < 1.3
  end
end
