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
    assert circular_stations.any? { |feature| feature.dig("properties", "ref") == "C14;O1" }
    refute circular_stations.any? { |feature| feature.dig("properties", "name") == "美麗島" }

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
