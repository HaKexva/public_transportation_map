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

  test "zhonghe xinlu minquan songjiang turn reaches into the intersection" do
    path = Rails.root.join("public/geojson/taipei_metro/zhonghe_xinlu.geojson")
    data = JSON.parse(path.read)
    luzhou_route = data.fetch("features").find { |f| f.dig("properties", "name")&.include?("蘆洲") }
    coords = luzhou_route.dig("geometry", "coordinates")
    at_minquan = coords.select { |lon, lat| (lat - 25.0625).abs < 0.0002 && lon > 121.53 }
    assert at_minquan.any?, "expected vertices near 民權路"
    assert_operator at_minquan.map(&:first).max, :>, 121.5324, "turn should reach into 民權松江路口"
  end

  test "zhonghe xinlu xujian sanmin segment stays near the station chord" do
    path = Rails.root.join("public/geojson/taipei_metro/zhonghe_xinlu.geojson")
    data = JSON.parse(path.read)
    luzhou_route = data.fetch("features").find { |f| f.dig("properties", "name")&.include?("蘆洲") }
    coords = luzhou_route.dig("geometry", "coordinates")
    xujian = [ 121.4802034, 25.080294 ]
    sanmin = [ 121.4732429, 25.0854517 ]
    ia = coords.each_with_index.min_by { |pt, _| Geojson::TrackGeometry.planar_distance_meters(pt[0], pt[1], *xujian) }.last
    ib = coords.each_with_index.min_by { |pt, _| Geojson::TrackGeometry.planar_distance_meters(pt[0], pt[1], *sanmin) }.last
    lo, hi = [ ia, ib ].minmax
    seg = coords[lo..hi]
    max_dev = seg.map { |pt| distance_to_segment_meters(pt, xujian, sanmin) }.max
    assert_operator max_dev, :<, 60, "徐匯–三民 should hug corridor (max #{max_dev.round(1)}m off chord)"
  end

  test "zhonghe xinlu luzhou depot spur reaches yard body and passenger tip stays local" do
    path = Rails.root.join("public/geojson/taipei_metro/zhonghe_xinlu.geojson")
    data = JSON.parse(path.read)
    luzhou_route = data.fetch("features").find { |f| f.dig("properties", "name")&.include?("蘆洲") }
    tip = luzhou_route.dig("geometry", "coordinates").first
    luzhou_station = [ 121.46509424179602, 25.09125852030004 ]
    tip_dist = Geojson::TrackGeometry.planar_distance_meters(tip[0], tip[1], *luzhou_station)
    assert_operator tip_dist, :<, 150, "蘆洲 passenger tip must not run deep into the depot"

    spur = data.fetch("features").find { |f| f.dig("properties", "depot_id") == "luzhou_depot" }
    assert spur
    spur_end = spur.dig("geometry", "coordinates").last
    assert_in_delta 121.47044, spur_end[0], 0.001
    assert_in_delta 25.09673, spur_end[1], 0.001
    assert_operator Geojson::TrackGeometry.path_length_meters(spur.dig("geometry", "coordinates")), :>, 800
  end

  test "zhonghe xinlu huilong passenger tip is a short stub not the depot throat" do
    path = Rails.root.join("public/geojson/taipei_metro/zhonghe_xinlu.geojson")
    data = JSON.parse(path.read)
    xinzhuang_route = data.fetch("features").find { |f| f.dig("properties", "name")&.include?("新莊") }
    tip = xinzhuang_route.dig("geometry", "coordinates").first
    huilong = [ 121.4119268323969, 25.02202627295023 ]
    tip_dist = Geojson::TrackGeometry.planar_distance_meters(tip[0], tip[1], *huilong)
    assert_operator tip_dist, :<, 120, "迴龍 tail must stay near the station (was #{tip_dist.round(1)}m)"
    assert_operator tip[0], :>, 121.410, "should not extend west into 新莊機廠 passenger geometry"

    spur = data.fetch("features").find { |f| f.dig("properties", "depot_id") == "xinzhuang_depot" }
    assert spur
    assert_operator spur.dig("geometry", "coordinates").last[0], :<, tip[0]
  end

  def distance_to_segment_meters(point, a, b)
    dx = b[0] - a[0]
    dy = b[1] - a[1]
    if dx == 0 && dy == 0
      return Geojson::TrackGeometry.planar_distance_meters(point[0], point[1], a[0], a[1])
    end

    t = (((point[0] - a[0]) * dx) + ((point[1] - a[1]) * dy)) / (dx * dx + dy * dy)
    t = [[ t, 0.0 ].max, 1.0 ].min
    proj = [ a[0] + t * dx, a[1] + t * dy ]
    Geojson::TrackGeometry.planar_distance_meters(point[0], point[1], proj[0], proj[1])
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
