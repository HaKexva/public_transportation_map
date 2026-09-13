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

    result = Geojson::BusStopIndexWriter.write!(bus_root: @root)
    assert_includes result.cities, "keelung_bus"

    data = JSON.parse(Geojson::BusStopIndexWriter.index_path_for("keelung_bus", bus_root: @root).read)
    assert_equal %w[keelung_901 keelung_902], data.dig("stations", "ST1").map { |row| row["id"] }.sort

    cluster = Geojson::BusStopClustering.cluster_key(name: "暖暖", lon: 121.75, lat: 25.10)
    assert_equal [ "keelung_902" ], data.dig("clusters", cluster).map { |row| row["id"] }
  end

  private

  def write_route!(slug, stations:)
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
      "features" => features
    }
    File.write(@city_dir.join("#{slug}.geojson"), "#{JSON.pretty_generate(payload)}\n")
  end
end
