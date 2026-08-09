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

  test "writes estimated mid-corridor crossing features" do
    count = Geojson::LevelCrossingCatalog.refresh!(
      output: @output,
      route_ids: [ @route.route_id ]
    )
    assert_operator count, :>=, 1

    data = JSON.parse(@output.read)
    assert_equal "FeatureCollection", data["type"]
    feature = data["features"].find { |row| row.dig("properties", "route_id") == @route.route_id }
    assert feature, "expected a crossing on #{@route.route_id}"
    assert feature.dig("properties", "estimate")
    assert_equal "Point", feature.dig("geometry", "type")
  end
end
