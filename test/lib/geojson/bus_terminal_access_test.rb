# frozen_string_literal: true

require "test_helper"

class Geojson::BusTerminalAccessTest < ActiveSupport::TestCase
  PATH = Geojson::BusTerminalAccess::PATHS.fetch("華江站")
  POLE = [ 121.4889513, 25.03228397 ].freeze
  STREET = [ [ 121.4920, 25.0306 ], [ 121.4907, 25.0314 ], [ 121.48899, 25.03234 ], POLE ].freeze

  test "routes into the depot at both termini and moves the terminal stop" do
    data = collection(
      route(0, STREET.reverse),
      route(1, STREET),
      station(0, "華江站", POLE),
      station(0, "大理高中", STREET.first),
      station(1, "大理高中", STREET.first),
      station(1, "華江站", POLE)
    )

    assert Geojson::BusTerminalAccess.process_collection!(data)

    outbound, inbound = data["features"].first(2).map { |feature| feature.dig("geometry", "coordinates") }
    assert_equal PATH.last, outbound.first
    assert_equal PATH.first, outbound[PATH.length - 1]
    assert_equal PATH.last, inbound.last
    assert_not_includes inbound, POLE
    terminals = data["features"].select { |feature| feature.dig("properties", "name") == "華江站" }
    assert(terminals.all? { |feature| feature.dig("geometry", "coordinates") == PATH.last })

    assert_not Geojson::BusTerminalAccess.process_collection!(data)
  end

  test "leaves other termini alone" do
    data = collection(route(1, STREET), station(1, "大理高中", STREET.first), station(1, "人壽一村", POLE))

    assert_not Geojson::BusTerminalAccess.process_collection!(data)
  end

  private

  def collection(*features)
    { "type" => "FeatureCollection", "features" => features }
  end

  def route(direction, coordinates)
    {
      "type" => "Feature",
      "properties" => { "feature_type" => "route", "direction" => direction },
      "geometry" => { "type" => "LineString", "coordinates" => coordinates.map(&:dup) }
    }
  end

  def station(direction, name, point)
    {
      "type" => "Feature",
      "properties" => { "feature_type" => "station", "direction" => direction, "name" => name },
      "geometry" => { "type" => "Point", "coordinates" => point.dup }
    }
  end
end
