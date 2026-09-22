# frozen_string_literal: true

require "test_helper"

class GeojsonBusCoverageAuditorTest < ActiveSupport::TestCase
  class FakeTdxClient
    def initialize(payloads)
      @payloads = payloads
    end

    def configured?
      true
    end

    def fetch_all(path)
      @payloads.fetch(path)
    end
  end

  setup do
    @output_dir = Rails.root.join("tmp/test_bus_coverage_#{SecureRandom.hex(4)}")
    @isolated_bus_root = Rails.root.join("tmp/test_bus_coverage_root_#{SecureRandom.hex(4)}")
    FileUtils.mkdir_p(@isolated_bus_root)
    @previous_bus_root = Geojson::BusLayout.instance_variable_get(:@bus_root_override)
    @previous_route_counts = Geojson::BusLayout.instance_variable_get(:@route_counts)
    # Empty isolated root: Miaoli routes look "not imported" without deleting shared fixtures.
    Geojson::BusLayout.bus_root = @isolated_bus_root
  end

  teardown do
    Geojson::BusLayout.instance_variable_set(:@bus_root_override, @previous_bus_root)
    Geojson::BusLayout.instance_variable_set(:@route_counts, @previous_route_counts)
    FileUtils.rm_rf(@output_dir)
    FileUtils.rm_rf(@isolated_bus_root) if @isolated_bus_root
  end

  test "flags TDX routes without shape and routes with shape not yet imported" do
    city = Geojson::BusCatalog.find("MiaoliCounty")
    client = FakeTdxClient.new(
      Geojson::BusImporter.route_path_for(city) => [
        route_record(uid: "MIA101", name: "101"),
        route_record(uid: "MIA102", name: "102"),
        route_record(uid: "MIA103", name: "103")
      ],
      Geojson::BusImporter.shape_path_for(city) => [
        shape_record(uid: "MIA101"),
        shape_record(uid: "MIA103")
      ],
      Geojson::BusImporter.stop_of_route_path_for(city) => []
    )

    report = Geojson::BusCoverageAuditor.audit!(
      city_ids: [ "MiaoliCounty" ],
      client: client,
      output_dir: @output_dir
    )

    city_report = report.cities.sole
    assert_equal "MiaoliCounty", city_report.city_id
    assert_equal 1, city_report.no_shape.length
    assert_equal %w[MIA102], city_report.no_shape.map(&:route_uid)
    assert_equal %w[miaoli_county_101 miaoli_county_103].sort, city_report.expected_slugs.sort
    assert_equal %w[miaoli_county_101 miaoli_county_103].sort, city_report.not_imported.map(&:slug).uniq.sort
    assert @output_dir.join("tdx_vs_local.md").exist?
    assert @output_dir.join("missing_official_maps.md").exist?
  end

  test "exports missing official map list from the local manifest" do
    report = Geojson::BusCoverageAuditor.export_local_gaps!(output_dir: @output_dir)

    assert report.missing_official_maps.any?
    markdown = @output_dir.join("missing_official_maps.md").read
    assert_includes markdown, "# Bus routes missing official map URL"
    assert_includes markdown, "**Total: #{report.missing_official_maps.length}**"
    assert_match(/## \w+ \(\d+\)/, markdown)
  end

  test "does not treat ChiayiCounty files as Chiayi city orphans" do
    city = Geojson::BusCatalog.find("Chiayi")
    client = FakeTdxClient.new(
      Geojson::BusImporter.route_path_for(city) => [],
      Geojson::BusImporter.shape_path_for(city) => [],
      Geojson::BusImporter.stop_of_route_path_for(city) => []
    )

    # Sibling county fixtures must not be attributed to the city prefix.
    FileUtils.mkdir_p(@isolated_bus_root.join("chiayi_county_bus"))
    File.write(
      @isolated_bus_root.join("chiayi_county_bus/chiayi_county_7202.geojson"),
      JSON.pretty_generate(
        {
          "type" => "FeatureCollection",
          "properties" => { "id" => "chiayi_county_7202", "city_id" => "ChiayiCounty" },
          "features" => []
        }
      )
    )

    report = Geojson::BusCoverageAuditor.audit!(
      city_ids: [ "Chiayi" ],
      client: client,
      output_dir: @output_dir
    )

    orphan_slugs = report.cities.sole.local_orphans.map(&:slug)
    refute orphan_slugs.any? { |slug| slug.start_with?("chiayi_county_") }
  end

  private

  def route_record(uid:, name:)
    {
      "RouteUID" => uid,
      "RouteName" => { "Zh_tw" => name, "En" => name },
      "Operators" => [
        {
          "OperatorID" => "Miaoli",
          "OperatorName" => { "Zh_tw" => "苗栗客運", "En" => "Miaoli Bus" }
        }
      ]
    }
  end

  def shape_record(uid:, wkt: "LINESTRING(120.8 24.5, 120.81 24.51)")
    {
      "RouteUID" => uid,
      "Direction" => 0,
      "Geometry" => wkt
    }
  end
end
