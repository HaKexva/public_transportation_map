# frozen_string_literal: true

require "test_helper"

class LevelCrossingCatalogTest < ActiveSupport::TestCase
  setup do
    @slug = "test_crossing_#{Process.pid}_#{SecureRandom.hex(4)}"
    @fixture = Rails.root.join("test/fixtures/files/geojson/test_chainage.geojson")
    @public_copy = Rails.root.join("public/geojson/#{@slug}.geojson")
    FileUtils.mkdir_p(@public_copy.dirname)
    FileUtils.cp(@fixture, @public_copy)

    @route = TransitRoute.create!(
      system_id: "tra",
      route_id: @slug,
      name: "測試平交道線",
      line_ref: "TX",
      geojson_path: "/geojson/#{@slug}.geojson"
    )
    %w[A B C D].each_with_index do |ref, index|
      names = { "A" => "甲", "B" => "乙", "C" => "丙", "D" => "丁" }
      TransitRouteStation.create!(
        transit_route: @route,
        station_ref: ref,
        name: names[ref],
        stop_sequence: index + 1,
        direction: TransitRoute::DIRECTION_BOTH
      )
    end
    Transit::GeojsonStationCoords.clear_cache!
    @output = Rails.root.join("tmp/#{@slug}_level_crossings.json")
  end

  teardown do
    @public_copy.delete if @public_copy&.exist?
    @output.delete if @output&.exist?
    Transit::GeojsonStationCoords.clear_cache!
  end

  test "snaps OSM level crossings onto TRA geometry and drops far ones" do
    nodes = [
      { "id" => 1, "lat" => 25.0001, "lon" => 121.0149, "tags" => { "railway" => "level_crossing", "name" => "測試路" } },
      { "id" => 2, "lat" => 25.0000, "lon" => 121.0240, "tags" => { "railway" => "level_crossing" } },
      { "id" => 3, "lat" => 25.0100, "lon" => 121.0150, "tags" => { "railway" => "level_crossing" } }
    ]

    count = Geojson::LevelCrossingCatalog.refresh!(
      output: @output,
      route_ids: [ @route.route_id ],
      fetcher: -> { nodes }
    )
    assert_equal 2, count

    data = JSON.parse(@output.read)
    assert_equal "FeatureCollection", data["type"]
    named, unnamed = data["features"].sort_by { |row| row.dig("properties", "id") }
    assert_equal "osm:1", named.dig("properties", "id")
    assert_equal "測試路", named.dig("properties", "name")
    assert_equal @route.route_id, named.dig("properties", "route_id")
    assert_equal [ 121.0149, 25.0001 ], named.dig("geometry", "coordinates")
    assert_equal "丙附近平交道", unnamed.dig("properties", "name")
  end
end
