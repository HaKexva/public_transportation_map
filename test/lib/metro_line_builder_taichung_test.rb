# frozen_string_literal: true

require "test_helper"

class MetroLineBuilderTaichungTest < ActiveSupport::TestCase
  test "taichung green line geojson is in Taiwan with 18 stations" do
    path = Rails.root.join("public/geojson/taichung_metro/green_line.geojson")
    skip "run bin/rails geojson:taichung_metro first" unless path.exist?

    data = JSON.parse(path.read)
    routes = data["features"].select { |feature| feature.dig("properties", "feature_type") == "route" }

    assert_equal 1, routes.length, "expected one merged green line track"

    route = routes.first
    first_coord = route.dig("geometry", "coordinates", 0)

    assert first_coord[0].between?(120.0, 121.5), "expected longitude in Taichung area"
    assert first_coord[1].between?(24.0, 24.5), "expected latitude in Taichung area"

    stations = data["features"].select { |feature| feature.dig("properties", "feature_type") == "station" }
    refs = stations.map { |feature| feature.dig("properties", "ref") }.sort

    assert_equal 18, stations.length
    assert_includes refs, "103a"
    assert_includes refs, "119"

    station_refs = stations.map { |feature| feature.dig("properties", "ref") }
    assert_equal "103a", station_refs.first, "expected 北屯總站 (103a) as the northern terminus"
    assert_equal "119", station_refs.last, "expected 高鐵臺中站 (119) as the southern terminus"
  end

  test "103a sorts before 103 for taichung station numbering" do
    builder = Geojson::MetroLineBuilder.new(Geojson::TaichungMetroCatalog::LINES.first)

    assert_equal(-1, builder.send(:station_sort_key, "103a") <=> builder.send(:station_sort_key, "103"))
  end
end
