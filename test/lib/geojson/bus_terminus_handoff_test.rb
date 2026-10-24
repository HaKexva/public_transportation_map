# frozen_string_literal: true

require "test_helper"

class GeojsonBusTerminusHandoffTest < ActiveSupport::TestCase
  # ~0.00001° lon ≈ 1 m at this latitude.
  def line(direction, coordinates)
    { "type" => "Feature", "properties" => { "feature_type" => "route", "direction" => direction },
      "geometry" => { "type" => "LineString", "coordinates" => coordinates } }
  end

  def stop(direction, name, coordinates)
    { "type" => "Feature", "properties" => { "feature_type" => "station", "direction" => direction, "name" => name },
      "geometry" => { "type" => "Point", "coordinates" => coordinates } }
  end

  def collection(outbound, inbound, stops)
    { "type" => "FeatureCollection", "features" => [ line(0, outbound), line(1, inbound), *stops ] }
  end

  test "outbound overshoot past the return trip's first stop moves to the return line" do
    data = collection(
      [ [ 121.5000, 25.1 ], [ 121.5050, 25.1 ], [ 121.5040, 25.1 ] ],
      [ [ 121.5040, 25.1 ], [ 121.5000, 25.1 ] ],
      [ stop(0, "振興街", [ 121.5050, 25.1 ]), stop(1, "榮總", [ 121.5045, 25.1 ]), stop(1, "北投站", [ 121.5000, 25.1 ]) ]
    )

    assert Geojson::BusTerminusHandoff.process_collection!(data)

    outbound, inbound = data["features"].first(2).map { |feature| feature.dig("geometry", "coordinates") }
    assert_equal [ 121.5045, 25.1 ], outbound.last
    assert_equal [ [ 121.5045, 25.1 ], [ 121.5, 25.1 ] ], inbound
    assert_not Geojson::BusTerminusHandoff.process_collection!(data)
  end

  test "drops the off-kerb join vertex but keeps a real turn there" do
    kink = [ [ 121.5045, 25.1 ], [ 121.5040, 25.10003 ], [ 121.5000, 25.1 ] ]
    corner = [ [ 121.5045, 25.1 ], [ 121.5040, 25.1 ], [ 121.5040, 25.0950 ] ]

    assert_equal [ kink.first, kink.last ], Geojson::BusTerminusHandoff.straighten_join(kink, 1)
    assert_equal corner, Geojson::BusTerminusHandoff.straighten_join(corner, 1)
  end

  test "leaves turnarounds the return line drives back through" do
    data = collection(
      [ [ 121.5000, 25.1 ], [ 121.5050, 25.1 ] ],
      [ [ 121.5050, 25.1 ], [ 121.5000, 25.1 ] ],
      [ stop(0, "A", [ 121.5000, 25.1 ]), stop(1, "B", [ 121.5045, 25.1 ]) ]
    )

    assert_not Geojson::BusTerminusHandoff.process_collection!(data)
  end

  test "never cuts off the outbound line's own last stop" do
    data = collection(
      [ [ 121.5000, 25.1 ], [ 121.5050, 25.1 ], [ 121.5040, 25.1 ] ],
      [ [ 121.5040, 25.1 ], [ 121.5000, 25.1 ] ],
      [ stop(0, "終點", [ 121.5042, 25.1 ]), stop(1, "起點", [ 121.5048, 25.1 ]) ]
    )

    assert_not Geojson::BusTerminusHandoff.process_collection!(data)
  end
end
