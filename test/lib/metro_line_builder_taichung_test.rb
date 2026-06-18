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
    assert_includes refs, "119;07;3340"

    station_refs = stations.map { |feature| feature.dig("properties", "ref") }
    assert_equal "103a", station_refs.first, "expected 北屯總站 (103a) as the northern terminus"
    assert_equal "119;07;3340", station_refs.last, "expected 高鐵臺中站 (119) as the southern terminus"
  end

  test "all stations match catalog coordinates (OSM / Wikipedia sources)" do
    path = Rails.root.join("public/geojson/taichung_metro/green_line.geojson")
    skip "run bin/rails geojson:taichung_metro first" unless path.exist?

    data = JSON.parse(path.read)
    catalog = Geojson::TaichungMetroCatalog::FALLBACK_STATIONS.index_by { |entry| entry[:ref] }

    catalog.each_key do |ref|
      feature = station_feature_for_ref(data, ref)
      assert feature, "missing station #{ref} in geojson"

      lon, lat = feature.dig("geometry", "coordinates")
      expected = catalog[ref]

      assert_equal expected[:name], feature.dig("properties", "name")
      assert_in_delta expected[:lon], lon, 0.000001, "longitude mismatch for #{ref}"
      assert_in_delta expected[:lat], lat, 0.000001, "latitude mismatch for #{ref}"
    end
  end

  test "九德 (117) is east of 烏日 (118) and both sit between 九張犁 and 高鐵臺中站 on the track" do
    path = Rails.root.join("public/geojson/taichung_metro/green_line.geojson")
    skip "run bin/rails geojson:taichung_metro first" unless path.exist?

    data = JSON.parse(path.read)
    route = data["features"].find { |f| f.dig("properties", "feature_type") == "route" }
    coordinates = route.dig("geometry", "coordinates")

    builder = Geojson::MetroLineBuilder.new(Geojson::TaichungMetroCatalog::LINES.first)
    stations = %w[116 117 118 119].to_h do |ref|
      feature = station_feature_for_ref(data, ref)
      lon, lat = feature.dig("geometry", "coordinates")
      [
        ref,
        {
          name: feature.dig("properties", "name"),
          lon: lon,
          lat: lat,
          chain_index: builder.send(:chain_index_for_station, { lon: lon, lat: lat }, [ coordinates ])
        }
      ]
    end

    assert_equal "九德", stations["117"][:name]
    assert_equal "烏日", stations["118"][:name]
    assert_operator stations["118"][:lon], :<, stations["117"][:lon], "烏日 should be west of 九德"

    assert_operator stations["116"][:chain_index], :<, stations["117"][:chain_index]
    assert_operator stations["116"][:chain_index], :<, stations["118"][:chain_index]
    assert_operator stations["117"][:chain_index], :<, stations["118"][:chain_index]
    assert_operator stations["118"][:chain_index], :<, stations["119"][:chain_index]
  end

  test "anchored taichung stations are not pulled onto the track when far from the centerline" do
    builder = Geojson::MetroLineBuilder.new(Geojson::TaichungMetroCatalog::LINES.first)
    line_strings = [ [ [ 120.61, 24.11 ], [ 120.62, 24.11 ] ] ]

    station = { lon: 120.641389, lat: 24.114444, position_anchored: true }
    builder.send(:align_stations_to_routes!, [ station ], [
      {
        properties: { feature_type: "route" },
        geometry: { coordinates: line_strings.first }
      }
    ])

    assert_in_delta 120.641389, station[:lon], 0.000001
    assert_in_delta 24.114444, station[:lat], 0.000001
  end

  test "103a sorts before 103 for taichung station numbering" do
    builder = Geojson::MetroLineBuilder.new(Geojson::TaichungMetroCatalog::LINES.first)

    assert_equal(-1, builder.send(:station_sort_key, "103a") <=> builder.send(:station_sort_key, "103"))
  end

  private

  def station_feature_for_ref(data, ref)
    data["features"].find do |feature|
      feature.dig("properties", "feature_type") == "station" &&
        feature.dig("properties", "ref").to_s.split(";").include?(ref)
    end
  end
end
