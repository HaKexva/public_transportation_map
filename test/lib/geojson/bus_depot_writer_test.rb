# frozen_string_literal: true

require "test_helper"

class GeojsonBusDepotWriterTest < ActiveSupport::TestCase
  setup do
    @root = Rails.root.join("tmp/bus_depot_writer_test_#{SecureRandom.hex(4)}")
    @city_dir = @root.join("keelung_bus")
    @out = @root.join("bus_depots.json")
    FileUtils.mkdir_p(@city_dir)
  end

  teardown do
    FileUtils.rm_rf(@root)
  end

  test "aggregates dispatch yards across routes and skips market parking noise" do
    write_route!(
      "keelung_602",
      name: "602",
      stations: [
        {
          "feature_type" => "station",
          "ref" => "KELDEPOT",
          "station_id" => "DEPOT1",
          "name" => "暖暖分站(調度站)",
          "stop_role" => "depot",
          "coordinates" => [ 121.74, 25.10 ]
        },
        {
          "feature_type" => "station",
          "ref" => "KELMKT",
          "name" => "立體停車場(五股公有市場)",
          "coordinates" => [ 121.45, 25.08 ]
        }
      ]
    )
    write_route!(
      "keelung_603",
      name: "603",
      stations: [
        {
          "feature_type" => "station",
          "ref" => "KELDEPOT2",
          "station_id" => "DEPOT1",
          "name" => "暖暖分站(調度站)",
          "coordinates" => [ 121.7401, 25.1001 ]
        }
      ]
    )

    result = Geojson::BusDepotWriter.write!(path: @out, bus_root: @root)
    assert_equal 1, result.depots.length
    depot = result.depots.first
    assert_equal "暖暖分站(調度站)", depot["name"]
    assert_equal %w[keelung_602 keelung_603], depot["routes"]
    assert_in_delta 121.74, depot["lon"], 0.001
    assert_in_delta 25.10, depot["lat"], 0.001
  end

  private

  def write_route!(slug, name:, stations:)
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
        "ref" => name,
        "name" => name,
        "color" => "#0B7A3E"
      },
      "features" => features
    }
    File.write(@city_dir.join("#{slug}.geojson"), "#{JSON.pretty_generate(payload)}\n")
  end
end
