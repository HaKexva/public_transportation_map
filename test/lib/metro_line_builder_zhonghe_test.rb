# frozen_string_literal: true

require "test_helper"

class MetroLineBuilderZhongheTest < ActiveSupport::TestCase
  test "zhonghe xinlu geojson includes main line and luzhou branch tracks" do
    path = Rails.root.join("public/geojson/taipei_metro/zhonghe_xinlu.geojson")
    skip "run bin/rails runner 'Geojson::MetroLineBuilder.build!(...)' for zhonghe_xinlu" unless path.exist?

    data = JSON.parse(path.read)
    route_lines = data["features"].filter_map do |feature|
      next unless feature.dig("properties", "feature_type") == "route"

      feature.dig("geometry", "coordinates")
    end

    assert_equal 2, route_lines.length, "expected main line and 蘆洲 branch as separate tracks"

    luzhou = data["features"].find do |feature|
      feature.dig("properties", "feature_type") == "station" &&
        feature.dig("properties", "name") == "蘆洲"
    end
    assert luzhou, "expected 蘆洲 station"

    lon, lat = luzhou.dig("geometry", "coordinates")
    distance = min_distance_to_lines_meters(lon, lat, route_lines)

    assert distance < 25, "expected 蘆洲 within 25m of a route track (was #{distance.round(1)}m)"
  end

  def min_distance_to_lines_meters(lon, lat, line_strings)
    builder = Geojson::MetroLineBuilder.new(Geojson::TaipeiMetroCatalog::LINES.first)

    line_strings.flat_map do |coordinates|
      coordinates.each_cons(2).map do |start, finish|
        _proj_lon, _proj_lat, distance = builder.send(:project_point_on_segment, lon, lat, start, finish)
        distance
      end
    end.min || Float::INFINITY
  end
end
