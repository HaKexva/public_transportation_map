# frozen_string_literal: true

require "test_helper"

class GeojsonBusCornerRounderTest < ActiveSupport::TestCase
  ORIGIN = [ 121.8, 25.1 ].freeze

  test "rounds a gentle bend on a sparse mountain trace into a wide arc" do
    line = [ at(0, 0), at(0, 60), at(16, 118) ] # ~15° bend, 60 m legs
    rounded = Geojson::BusCornerRounder.round_line(line)

    assert_operator rounded.length, :>, line.length
    assert_equal line.first, rounded.first
    assert_equal line.last, rounded.last
    # The arc spans most of both legs instead of a kink at the vertex.
    assert_operator distance(rounded[1], line[1]), :>, 20
    assert_operator max_turn_degrees(rounded), :<, 10
  end

  test "keeps a junction turn tight and close to the corner" do
    line = [ at(0, -100), at(0, 0), at(100, 0) ]
    rounded = Geojson::BusCornerRounder.round_line(line)

    closest = rounded.map { |point| distance(point, line[1]) }.min
    assert_operator closest, :<=, Geojson::BusCornerRounder::MAX_DEVIATION_M + 0.1
    assert_operator distance(rounded[1], line[1]), :<, 16
  end

  test "never lets arcs on consecutive corners overlap" do
    line = [ at(0, 0), at(0, 10), at(10, 10), at(10, 20) ]
    rounded = Geojson::BusCornerRounder.round_line(line)

    ys = rounded.map { |point| local(point)[1] }
    assert_equal ys, ys.sort
  end

  test "leaves straight runs and turnaround reversals alone" do
    straight = [ at(0, 0), at(0, 50), at(0.5, 100) ]
    assert_equal straight, Geojson::BusCornerRounder.round_line(straight)

    reversal = [ at(0, 0), at(0, 50), at(2, 0) ]
    assert_equal reversal, Geojson::BusCornerRounder.round_line(reversal)
  end

  test "rounds each route once" do
    data = { "features" => [
      { "properties" => { "feature_type" => "route" }, "geometry" => { "type" => "LineString", "coordinates" => [ at(0, 0), at(0, 60), at(30, 110) ] } },
      { "properties" => { "feature_type" => "station" }, "geometry" => { "type" => "Point", "coordinates" => at(0, 60) } }
    ] }

    assert Geojson::BusCornerRounder.process_collection!(data)
    once = data["features"].first["geometry"]["coordinates"].dup
    assert_not Geojson::BusCornerRounder.process_collection!(data)
    assert_equal once, data["features"].first["geometry"]["coordinates"]
    assert_equal at(0, 60), data["features"].last["geometry"]["coordinates"]
  end

  private

  def at(east, north)
    [ ORIGIN[0] + (east / (111_320.0 * Math.cos(ORIGIN[1] * Math::PI / 180))), ORIGIN[1] + (north / 110_540.0) ]
  end

  def local(point)
    [ (point[0] - ORIGIN[0]) * 111_320.0 * Math.cos(ORIGIN[1] * Math::PI / 180), (point[1] - ORIGIN[1]) * 110_540.0 ]
  end

  def distance(first, second)
    a = local(first)
    b = local(second)
    Math.hypot(a[0] - b[0], a[1] - b[1])
  end

  def max_turn_degrees(line)
    line.map { |point| local(point) }.each_cons(3).map do |a, b, c|
      first = Math.atan2(b[1] - a[1], b[0] - a[0])
      second = Math.atan2(c[1] - b[1], c[0] - b[0])
      diff = (second - first).abs % (2 * Math::PI)
      [ diff, (2 * Math::PI) - diff ].min * 180 / Math::PI
    end.max
  end
end
