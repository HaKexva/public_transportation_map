# frozen_string_literal: true

require "test_helper"

class MetroLineBuilderGuangfuTest < ActiveSupport::TestCase
  test "guangfu sugar railway keeps short remnant not full yard loop" do
    path = Rails.root.join("public/geojson/sugar_railway/guangfu_sugar_railway.geojson")
    skip "run bin/rails geojson:sugar_railway first" unless path.exist?

    data = JSON.parse(path.read)
    route = data.fetch("features").find { |feature| feature.dig("properties", "feature_type") == "route" }
    assert route, "expected a route feature"

    coordinates = route.dig("geometry", "coordinates")
    length = coordinates.each_cons(2).sum do |left, right|
      Geojson::TrackGeometry.planar_distance_meters(left[0], left[1], right[0], right[1])
    end

    assert_operator length, :<, 350, "should not draw the full ~2.3 km factory loop"
    assert_operator length, :>, 80
    assert_operator coordinates.map { |point| point[0] }.max, :<, 121.4225
    assert_operator coordinates.map { |point| point[1] }.min, :>, 23.657
  end

  test "clip_guangfu_sugar_factory_loop trims a long yard loop" do
    line = Geojson::SugarRailwayCatalog::LINES.find { |entry| entry.slug == "guangfu_sugar_railway" }
    builder = Geojson::MetroLineBuilder.new(line)

    loop_coords = [
      [ 121.4203, 23.6550 ],
      [ 121.4255, 23.6610 ],
      [ 121.4206, 23.6595 ],
      [ 121.4201, 23.6586 ],
      [ 121.4182, 23.6545 ],
      [ 121.4203, 23.6550 ]
    ]
    features = [ {
      type: "Feature",
      properties: { feature_type: "route", ref: "GF", name: "花蓮觀光糖廠五分車" },
      geometry: { type: "LineString", coordinates: loop_coords }
    } ]

    builder.send(:clip_guangfu_sugar_factory_loop!, features)
    clipped = features.first.dig(:geometry, :coordinates)
    length = clipped.each_cons(2).sum do |left, right|
      Geojson::TrackGeometry.planar_distance_meters(left[0], left[1], right[0], right[1])
    end

    assert_operator length, :<, 350
    assert clipped.any? { |lon, lat| (lon - 121.4206).abs < 0.001 && (lat - 23.6595).abs < 0.001 }
    assert clipped.any? { |lon, lat| (lon - 121.4201).abs < 0.001 && (lat - 23.6586).abs < 0.001 }
  end
end
