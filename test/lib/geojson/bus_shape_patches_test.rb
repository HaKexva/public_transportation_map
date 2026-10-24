# frozen_string_literal: true

require "test_helper"

class Geojson::BusShapePatchesTest < ActiveSupport::TestCase
  STOP = [ 121.5921, 25.07185 ].freeze
  CIRCULATION = Geojson::BusShapePatches::STOP_CIRCULATIONS.fetch("三總內湖站")

  test "replaces a hospital visit from 成功路 with the internal loop and drops entrance spikes" do
    line = [
      [ 121.5899, 25.0740 ], [ 121.58981, 25.07174 ],
      [ 121.5910, 25.07170 ], [ 121.5920, 25.07155 ], [ 121.5920, 25.07235 ], [ 121.5910, 25.07195 ],
      [ 121.58988, 25.07197 ], [ 121.58972, 25.07161 ], [ 121.58971, 25.07183 ], [ 121.58972, 25.07161 ],
      [ 121.5905, 25.0690 ]
    ]
    data = collection(route(0, line), station(0, "三總內湖站", STOP))

    assert Geojson::BusShapePatches.process_collection!(data)

    patched = data["features"].first.dig("geometry", "coordinates")
    assert_equal line.first(2), patched.first(2)
    assert_equal CIRCULATION[:paths][:west], patched[2, CIRCULATION[:paths][:west].length]
    assert_equal [ [ 121.58988, 25.07197 ], [ 121.58972, 25.07161 ], [ 121.5905, 25.0690 ] ], patched.last(3)

    assert_not Geojson::BusShapePatches.process_collection!(data)
  end

  test "routes the arrival into 萬芳社區 through the bus lot instead of across the block" do
    terminal = Geojson::BusShapePatches::TERMINAL_APPROACHES.find { |entry| entry[:name] == "萬芳社區" }
    line = [ [ 121.568900, 25.002420 ], [ 121.569813, 25.002290 ], [ 121.570480, 25.001756 ] ]
    data = collection(route(1, line))

    assert Geojson::BusShapePatches.process_collection!(data)
    assert_equal line.first(2) + terminal[:path] + [ line.last ], data["features"].first.dig("geometry", "coordinates")
    assert_not Geojson::BusShapePatches.process_collection!(data)
  end

  test "runs both halves of the 陽明山國家公園管理處 terminal loop" do
    terminal = Geojson::BusShapePatches::TERMINAL_LOOPS.find { |entry| entry[:name] == "陽明山國家公園管理處" }
    arrival = [ [ 121.546500, 25.154900 ], [ 121.546180, 25.155230 ], [ 121.546020, 25.155400 ],
                [ 121.545700, 25.155130 ], [ 121.544520, 25.154110 ], [ 121.544700, 25.153900 ] ]
    departure = [ [ 121.544700, 25.153900 ], [ 121.545400, 25.154000 ], [ 121.546070, 25.155220 ],
                  [ 121.546200, 25.155140 ], [ 121.546500, 25.154900 ] ]
    data = collection(route(0, arrival), route(1, departure))

    assert Geojson::BusShapePatches.process_collection!(data)
    patched_arrival, patched_departure = data["features"].map { |feature| feature.dig("geometry", "coordinates") }
    assert_equal arrival.first(2) + terminal[:arrival], patched_arrival
    assert_equal terminal[:departure] + departure.last(1), patched_departure
    assert_not Geojson::BusShapePatches.process_collection!(data)
  end

  test "leaves directions that do not stop there alone" do
    line = [ [ 121.58981, 25.07174 ], [ 121.5915, 25.0712 ], [ 121.5950, 25.0708 ] ]
    data = collection(route(1, line), station(1, "將軍嶺", [ 121.5880, 25.0700 ]))

    assert_not Geojson::BusShapePatches.process_collection!(data)
  end

  test "drops a detour loop between the first and last pass of its junction" do
    junction = [ 121.583855, 25.038199 ]
    loop = [ [ 121.5830, 25.0400 ], [ 121.5800, 25.0420 ], [ 121.5780, 25.0380 ], [ 121.5820, 25.0376 ] ]
    line = [ [ 121.5870, 25.0392 ], junction ] + loop + [ [ 121.583894, 25.038110 ], [ 121.5800, 25.0366 ] ]

    patched = Geojson::BusShapePatches.drop_excursion(line, junction)

    assert_equal [ [ 121.5870, 25.0392 ], junction, [ 121.5800, 25.0366 ] ], patched
    assert_equal line, Geojson::BusShapePatches.drop_excursion(line, [ 121.60, 25.05 ])
  end

  private

  def collection(*features)
    { "type" => "FeatureCollection", "properties" => { "id" => "test_route" }, "features" => features }
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
