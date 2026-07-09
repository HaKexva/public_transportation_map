# frozen_string_literal: true

require "test_helper"

class MetroLineBuilderSanyingTest < ActiveSupport::TestCase
  test "sanying line includes all twelve stations in order" do
    path = Rails.root.join("public/geojson/new_taipei_metro/sanying_line.geojson")
    skip "run bin/rails geojson:new_taipei_metro first" unless path.exist?

    data = JSON.parse(path.read)
    stations = data["features"].select { |feature| feature.dig("properties", "feature_type") == "station" }

    refs = stations.map { |feature| feature.dig("properties", "ref") }
    assert_equal (1..12).map { |index| format("LB%02d", index) }, refs

    assert_equal "頂埔", stations.first.dig("properties", "name")
    assert_equal "鶯桃福德", stations.last.dig("properties", "name")
    assert_equal "#6DB7D0", stations.first.dig("properties", "color")

    refute stations.any? { |feature| feature.dig("properties", "station_role").present? },
           "routes should not mark origin/destination terminals"
  end
end
