# frozen_string_literal: true

require "test_helper"

class MetroLineBuilderKaohsiungTest < ActiveSupport::TestCase
  test "kaohsiung lines geojson are in Taiwan with expected transfer station" do
    red_path = Rails.root.join("public/geojson/kaohsiung_metro/red_line.geojson")
    orange_path = Rails.root.join("public/geojson/kaohsiung_metro/orange_line.geojson")
    circular_path = Rails.root.join("public/geojson/kaohsiung_metro/circular_lrt.geojson")
    skip "run bin/rails geojson:kaohsiung_metro first" unless red_path.exist? && orange_path.exist? && circular_path.exist?

    [ red_path, orange_path, circular_path ].each do |path|
      data = JSON.parse(path.read)
      route = data["features"].find { |feature| feature.dig("properties", "feature_type") == "route" }
      first_coord = route.dig("geometry", "coordinates", 0)

      assert first_coord[0].between?(120.0, 121.0), "expected longitude in Kaohsiung area for #{path.basename}"
      assert first_coord[1].between?(22.0, 23.5), "expected latitude in Kaohsiung area for #{path.basename}"
    end

    red_stations = JSON.parse(red_path.read)["features"].select { |f| f.dig("properties", "feature_type") == "station" }
    orange_stations = JSON.parse(orange_path.read)["features"].select { |f| f.dig("properties", "feature_type") == "station" }

    assert red_stations.any? { |feature| feature.dig("properties", "ref") == "R10;O5" }
    assert orange_stations.any? { |feature| feature.dig("properties", "ref") == "R10;O5" }

    terminal = red_stations.find { |feature| feature.dig("properties", "ref") == "RK1" }
    assert terminal, "expected RK1 岡山車站 as red line northern terminus"
    assert_equal "岡山車站", terminal.dig("properties", "name")

    circular_stations = JSON.parse(circular_path.read)["features"].select { |f| f.dig("properties", "feature_type") == "station" }
    assert circular_stations.any? { |feature| feature.dig("properties", "ref") == "C1" }
    assert circular_stations.any? { |feature| feature.dig("properties", "ref") == "C14" }
    assert orange_stations.any? { |feature| feature.dig("properties", "ref") == "O1" }
    refute circular_stations.any? { |feature| feature.dig("properties", "name") == "美麗島" }

    hamasing_circular = circular_stations.find { |feature| feature.dig("properties", "ref") == "C14" }
    hamasing_orange = orange_stations.find { |feature| feature.dig("properties", "ref") == "O1" }
    circular_coords = hamasing_circular.dig("geometry", "coordinates")
    orange_coords = hamasing_orange.dig("geometry", "coordinates")
    spread = Geojson::TrackGeometry.planar_distance_meters(
      circular_coords[0], circular_coords[1], orange_coords[0], orange_coords[1]
    )
    assert spread > 150, "expected C14 and O1 platforms to be separate (was #{spread.round(1)}m apart)"

    refute circular_stations.any? { |feature| feature.dig("properties", "station_role").present? },
           "loop line should not mark origin/destination terminals"

    red_routes = JSON.parse(red_path.read)["features"].count { |f| f.dig("properties", "feature_type") == "route" }
    orange_routes = JSON.parse(orange_path.read)["features"].count { |f| f.dig("properties", "feature_type") == "route" }

    assert_equal 1, red_routes, "expected one merged red line track"
    assert_equal 1, orange_routes, "expected one merged orange line track"

    route_lines = JSON.parse(circular_path.read)["features"].filter_map do |feature|
      next unless feature.dig("properties", "feature_type") == "route"

      feature.dig("geometry", "coordinates")
    end
    assert_equal 1, route_lines.length, "expected a single stitched circular lrt route line"

    circular_stations.each do |station|
      lon, lat = station.dig("geometry", "coordinates")
      ref = station.dig("properties", "ref")
      distance = min_distance_to_lines_meters(lon, lat, route_lines)

      assert distance < 25, "expected #{ref} within 25m of track (was #{distance.round(1)}m)"
    end
  end

  test "red line R4A sits near the passenger centerline and Xiaogang stub is short" do
    path = Rails.root.join("public/geojson/kaohsiung_metro/red_line.geojson")
    skip "run bin/rails geojson:kaohsiung_metro first" unless path.exist?

    data = JSON.parse(path.read)
    route = data["features"].find { |feature| feature.dig("properties", "feature_type") == "route" }
    coordinates = route.dig("geometry", "coordinates")
    stations = data["features"].select { |feature| feature.dig("properties", "feature_type") == "station" }

    r4a = stations.find { |feature| feature.dig("properties", "ref") == "R4A" }
    r3 = stations.find { |feature| feature.dig("properties", "ref") == "R3" }
    assert r4a && r3

    builder = Geojson::MetroLineBuilder.new(Geojson::KaohsiungMetroCatalog::LINES.find { |line| line.slug == "red_line" })
    i4a = builder.send(:nearest_coordinate_index, coordinates, r4a["geometry"]["coordinates"])
    i3 = builder.send(:nearest_coordinate_index, coordinates, r3["geometry"]["coordinates"])

    r4a_distance = Geojson::TrackGeometry.planar_distance_meters(
      coordinates[i4a][0], coordinates[i4a][1],
      r4a["geometry"]["coordinates"][0], r4a["geometry"]["coordinates"][1]
    )
    stub_m = Geojson::TrackGeometry.path_length_meters(coordinates[i3..])

    assert_operator r4a_distance, :<, 55, "R4A should sit near dual-track/NLSC centerline (was #{r4a_distance.round(1)}m)"
    assert_operator stub_m, :<=, 110, "小港 stub should be short (was #{stub_m.round(1)}m)"
  end

  test "red line south depot spur peels near R4A into the yard body" do
    path = Rails.root.join("public/geojson/kaohsiung_metro/red_line.geojson")
    skip "run bin/rails geojson:kaohsiung_metro first" unless path.exist?

    data = JSON.parse(path.read)
    spur = data["features"].find { |feature| feature.dig("properties", "depot_id") == "kaohsiung_south_depot" }
    assert spur, "expected 南機廠支線"

    coords = spur.dig("geometry", "coordinates")
    assert_operator coords.length, :>=, 3
    assert_in_delta 120.33057, coords.last[0], 0.001
    assert_in_delta 22.58453, coords.last[1], 0.001
    assert_operator coords.first[1], :<, 22.5815, "spur should peel near R4A, not deep in the yard"
  end

  test "orange line O2-O4 corridor is dense and daliao depot spur goes north into the yard" do
    path = Rails.root.join("public/geojson/kaohsiung_metro/orange_line.geojson")
    skip "run bin/rails geojson:kaohsiung_metro first" unless path.exist?

    data = JSON.parse(path.read)
    route = data["features"].find { |feature| feature.dig("properties", "feature_type") == "route" }
    coordinates = route.dig("geometry", "coordinates")
    stations = data["features"].select { |feature| feature.dig("properties", "feature_type") == "station" }

    o2 = stations.find { |feature| feature.dig("properties", "ref") == "O2" }
    o4 = stations.find { |feature| feature.dig("properties", "ref") == "O4" }
    assert o2 && o4

    builder = Geojson::MetroLineBuilder.new(
      Geojson::KaohsiungMetroCatalog::LINES.find { |line| line.slug == "orange_line" }
    )
    i2 = builder.send(:nearest_coordinate_index, coordinates, o2["geometry"]["coordinates"])
    i4 = builder.send(:nearest_coordinate_index, coordinates, o4["geometry"]["coordinates"])
    lo, hi = [ i2, i4 ].minmax
    max_step = (lo...hi).map do |index|
      Geojson::TrackGeometry.planar_distance_meters(
        coordinates[index][0], coordinates[index][1],
        coordinates[index + 1][0], coordinates[index + 1][1]
      )
    end.max

    assert_operator max_step, :<, 50, "O2–O4 should not use sparse 300m chords (was #{max_step.round(1)}m)"

    spur = data["features"].find { |feature| feature.dig("properties", "depot_id") == "kaohsiung_daliao_depot" }
    assert spur, "expected 大寮機廠支線"
    coords = spur.dig("geometry", "coordinates")
    assert_operator coords.last[1], :>, coords.first[1], "spur should run north into the yard"
    assert_in_delta 120.39072, coords.last[0], 0.002
    assert_in_delta 22.62487, coords.last[1], 0.002
  end

  def min_distance_to_lines_meters(lon, lat, line_strings)
    line_strings.flat_map do |coordinates|
      coordinates.each_cons(2).map do |start, finish|
        _proj_lon, _proj_lat, distance = Geojson::MetroLineBuilder.new(
          Geojson::KaohsiungMetroCatalog::LINES.first
        ).send(:project_point_on_segment, lon, lat, start, finish)
        distance
      end
    end.min || Float::INFINITY
  end
end
