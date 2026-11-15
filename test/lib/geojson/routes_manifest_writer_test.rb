# frozen_string_literal: true

require "test_helper"

class Geojson::RoutesManifestWriterTest < ActiveSupport::TestCase
  test "bus termini prefer outbound stop poles over Route 起迄" do
    data = {
      "properties" => {
        "departure" => "板橋",
        "destination" => "南天母廣場",
        "departure_en" => "Banqiao",
        "destination_en" => "Nantianmu Square"
      },
      "features" => [
        station("南雅站", "Nanya", 0),
        station("南天母路二", "Nantianmu Rd. 2", 0)
      ]
    }

    assert_equal(
      {
        "departure" => "南雅站",
        "destination" => "南天母路二",
        "departure_en" => "Nanya",
        "destination_en" => "Nantianmu Rd. 2"
      },
      Geojson::RoutesManifestWriter.termini_for(data)
    )
  end

  test "bus termini fall back to stored Route 起迄 on loop routes" do
    data = {
      "properties" => {
        "departure" => "捷運淡水站",
        "destination" => "沙崙",
        "departure_en" => "MRT Tamsui Sta.",
        "destination_en" => "Shalun",
        "loop" => true
      },
      "features" => [
        station("捷運淡水站", "MRT Tamsui Sta.", 0),
        station("沙崙", "Shalun", 0),
        station("捷運淡水站", "MRT Tamsui Sta.", 0)
      ]
    }

    assert_equal(
      {
        "departure" => "捷運淡水站",
        "destination" => "沙崙",
        "departure_en" => "MRT Tamsui Sta.",
        "destination_en" => "Shalun",
        "loop" => true
      }.except("loop"),
      Geojson::RoutesManifestWriter.termini_for(data)
    )
  end

  test "574 termini override still wins" do
    data = {
      "properties" => {
        "id" => "new_taipei_574",
        "departure" => "板橋",
        "destination" => "南天母廣場"
      },
      "features" => [
        station("南雅站", "Nanya", 0),
        station("南天母廣場", "Nantianmu Square", 0)
      ]
    }

    termini = Geojson::RoutesManifestWriter.termini_for(data)
    assert_equal "信義國小", termini["departure"]
    assert_equal "南天母廣場", termini["destination"]
  end

  test "rail entries carry a bounding box for nearby lookups" do
    Dir.mktmpdir do |dir|
      path = Pathname.new(dir).join("routes.json")
      capture_io { Geojson::RoutesManifestWriter.write!(path: path, bus_path: nil) }
      manifest = JSON.parse(path.read)

      hsr = manifest.fetch("hsr").find { |entry| entry["id"] == "taiwan_hsr" }
      min_lng, min_lat, max_lng, max_lat = hsr.fetch("bbox")
      assert_operator min_lng, :<, max_lng
      assert_operator min_lat, :<, max_lat
      assert_in_delta 120.3, min_lng, 0.3
      assert_in_delta 25.05, max_lat, 0.1
    end
  end

  test "classifies outbound-only bus shapes as one_way but not loops" do
    writer = Geojson::RoutesManifestWriter.allocate
    one_way = {
      "features" => [ line(0), station("A", "A", 0), station("B", "B", 0) ]
    }
    loop_route = {
      "features" => [ line(0), station("A", "A", 0), station("A", "A", 0) ]
    }
    both = {
      "features" => [ line(0), line(1) ]
    }

    assert writer.send(:one_way_bus?, one_way, {})
    assert_not writer.send(:one_way_bus?, loop_route, { "loop" => true })
    assert_not writer.send(:one_way_bus?, both, {})
  end

  private

  def line(direction)
    {
      "type" => "Feature",
      "properties" => { "feature_type" => "route", "direction" => direction },
      "geometry" => { "type" => "LineString", "coordinates" => [ [ 121.0, 25.0 ], [ 121.1, 25.1 ] ] }
    }
  end

  def station(name, name_en, direction)
    {
      "properties" => {
        "feature_type" => "station",
        "name" => name,
        "name_en" => name_en,
        "direction" => direction
      }
    }
  end
end
