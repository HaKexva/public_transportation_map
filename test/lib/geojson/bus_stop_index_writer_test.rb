# frozen_string_literal: true

require "test_helper"

class GeojsonBusStopIndexWriterTest < ActiveSupport::TestCase
  setup do
    @root = Rails.root.join("tmp/bus_stop_index_test_#{SecureRandom.hex(4)}")
    @city_dir = @root.join("keelung_bus")
    FileUtils.mkdir_p(@city_dir)
  end

  teardown do
    FileUtils.rm_rf(@root)
  end

  test "indexes routes by station_id and coordinate cluster" do
    write_route!(
      "keelung_901",
      stations: [
        {
          "feature_type" => "station",
          "ref" => "KEL1",
          "station_id" => "ST1",
          "name" => "基隆車站",
          "coordinates" => [ 121.7394, 25.1318 ]
        }
      ]
    )
    write_route!(
      "keelung_902",
      stations: [
        {
          "feature_type" => "station",
          "ref" => "KEL2",
          "station_id" => "ST1",
          "name" => "基隆車站",
          "coordinates" => [ 121.7395, 25.1319 ]
        },
        {
          "feature_type" => "station",
          "ref" => "KEL3",
          "name" => "暖暖",
          "coordinates" => [ 121.75, 25.10 ]
        }
      ]
    )

    result = Geojson::BusStopIndexWriter.write!(bus_root: @root, road_names: nil)
    assert_includes result.cities, "keelung_bus"

    data = JSON.parse(Geojson::BusStopIndexWriter.index_path_for("keelung_bus", bus_root: @root).read)
    assert_equal %w[keelung_901 keelung_902], data.dig("stations", "ST1").map { |row| row["id"] }.sort

    cluster = Geojson::BusStopClustering.cluster_key(name: "暖暖", lon: 121.75, lat: 25.10)
    assert_equal [ "keelung_902" ], data.dig("clusters", cluster).map { |row| row["id"] }
  end

  test "describes each stop group by its street and the next stop" do
    # East-west 忠一路 along y = 25.1300, with 信二路 crossing it at x = 121.7400.
    ways = [
      { "c" => [ [ 121.7350, 25.1300 ], [ 121.7450, 25.1300 ] ], "n" => "忠一路" },
      { "c" => [ [ 121.7400, 25.1250 ], [ 121.7400, 25.1350 ] ], "n" => "信二路" }
    ]
    road_names = Geojson::OsmRoadNames.new(tile_loader: ->(_key) { ways })
    write_route!(
      "keelung_903",
      line: { "0" => [ [ 121.7380, 25.1301 ], [ 121.7420, 25.1301 ] ], "1" => [ [ 121.7420, 25.1299 ], [ 121.7380, 25.1299 ] ] },
      stations: [
        { "feature_type" => "station", "direction" => 0, "station_id" => "E", "name" => "信二路口", "coordinates" => [ 121.7399, 25.1302 ] },
        { "feature_type" => "station", "direction" => 0, "name" => "海洋廣場", "coordinates" => [ 121.7420, 25.1301 ] },
        { "feature_type" => "station", "direction" => 1, "station_id" => "W", "name" => "信二路口", "coordinates" => [ 121.7401, 25.1298 ] },
        { "feature_type" => "station", "direction" => 1, "name" => "基隆車站", "coordinates" => [ 121.7380, 25.1299 ] }
      ]
    )

    Geojson::BusStopIndexWriter.write!(bus_root: @root, road_names:)
    index = JSON.parse(Geojson::BusStopIndexWriter.index_path_for("keelung_bus", bus_root: @root).read)
    assert_equal [ "海洋廣場" ], index.dig("stations", "E", 0, "toward")
    assert_equal [ "基隆車站" ], index.dig("stations", "W", 0, "toward")
    terminus = index.dig("clusters", Geojson::BusStopClustering.cluster_key(name: "海洋廣場", lon: 121.7420, lat: 25.1301), 0)
    assert_nil terminus["toward"]
    assert terminus["terminus"]
    groups = index["groups"]
    assert_equal({ "road" => "忠一路", "toward" => "海洋廣場" }, groups["E"].slice("road", "toward"))
    assert_equal({ "road" => "忠一路", "toward" => "基隆車站" }, groups["W"].slice("road", "toward"))
  end

  test "splits one TDX station into its terminal platforms" do
    write_route!(
      "keelung_904",
      stations: [
        { "feature_type" => "station", "ref" => "P1", "station_id" => "BQ", "platform" => "第一月台", "name" => "新北板橋公車站", "coordinates" => [ 121.4625, 25.0128 ] },
        { "feature_type" => "station", "ref" => "X", "name" => "海洋廣場", "coordinates" => [ 121.47, 25.02 ] }
      ]
    )
    write_route!(
      "keelung_905",
      stations: [
        { "feature_type" => "station", "ref" => "P4", "station_id" => "BQ", "platform" => "第四月台", "name" => "新北板橋公車站", "coordinates" => [ 121.4622, 25.0128 ] }
      ]
    )

    Geojson::BusStopIndexWriter.write!(bus_root: @root, road_names: nil)
    index = JSON.parse(Geojson::BusStopIndexWriter.index_path_for("keelung_bus", bus_root: @root).read)

    assert_nil index.dig("stations", "BQ")
    assert_equal [ "keelung_904" ], index.dig("stations", "BQ@第一月台").map { |row| row["id"] }
    assert_equal [ "keelung_905" ], index.dig("stations", "BQ@第四月台").map { |row| row["id"] }
    assert_equal({ "platform" => "第四月台", "platform_en" => "Platform 4", "stops" => [ "P4" ] },
      index.dig("groups", "BQ@第四月台").slice("platform", "platform_en", "stops"))
  end

  test "translates platform names" do
    assert_equal [ "Platform 1", "Platform 12", "Platform A", "Platform 3" ],
      %w[第一月台 第十二月台 A月台 3號月台].map { |name| Geojson::BusStopIndexWriter.platform_en(name) }
  end

  private

  def write_route!(slug, stations:, line: {})
    routes = line.map do |direction, coordinates|
      {
        "type" => "Feature",
        "properties" => { "feature_type" => "route", "direction" => direction.to_i },
        "geometry" => { "type" => "LineString", "coordinates" => coordinates }
      }
    end
    features = stations.map { |station|
      {
        "type" => "Feature",
        "properties" => station.except("coordinates"),
        "geometry" => { "type" => "Point", "coordinates" => station["coordinates"] }
      }
    }
    payload = {
      "type" => "FeatureCollection",
      "properties" => {
        "id" => slug,
        "city_id" => "Keelung",
        "ref" => slug.split("_").last,
        "name" => slug.split("_").last,
        "color" => "#0B7A3E"
      },
      "features" => routes + features
    }
    File.write(@city_dir.join("#{slug}.geojson"), "#{JSON.pretty_generate(payload)}\n")
  end
end
