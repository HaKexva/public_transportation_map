# frozen_string_literal: true

require "test_helper"

class GeojsonBusShapeSharpenerTest < ActiveSupport::TestCase
  test "replaces a diagonal corner cut with a small fillet arc near the junction" do
    # East along a street, diagonal through the junction, then north.
    line = [
      [ 121.7400, 25.1300 ],
      [ 121.7410, 25.1300 ],
      [ 121.7415, 25.1305 ], # diagonal cut
      [ 121.7415, 25.1315 ],
      [ 121.7415, 25.1325 ]
    ]

    sharpened = Geojson::BusShapeSharpener.sharpen(line)
    junction = [ 121.7415, 25.1300 ]

    assert_equal line.first, sharpened.first
    assert_equal line.last, sharpened.last
    # Arc adds vertices beyond the original diagonal cut.
    assert_operator sharpened.length, :>=, 4

    nearest = sharpened.min_by { |point| meters_between(point, junction) }
    assert_operator meters_between(nearest, junction), :<, 14.0

    # Interior samples should sit off the sharp L (arc bulge ≈ radius).
    interior = sharpened[1...-1]
    assert_operator interior.length, :>=, 2
    max_from_legs = interior.map { |point| distance_to_l_legs(point, junction) }.max
    assert_operator max_from_legs, :>, 1.0
    assert_operator max_from_legs, :<, 14.0
  end

  test "leaves a gentle curve unchanged" do
    line = [
      [ 121.7400, 25.1300 ],
      [ 121.7410, 25.1301 ],
      [ 121.7420, 25.1304 ],
      [ 121.7430, 25.1309 ],
      [ 121.7440, 25.1316 ],
      [ 121.7450, 25.1325 ]
    ]

    sharpened = Geojson::BusShapeSharpener.sharpen(line)

    assert_equal line.length, sharpened.length
    line.each_with_index do |point, index|
      assert_in_delta point[0], sharpened[index][0], 1e-9
      assert_in_delta point[1], sharpened[index][1], 1e-9
    end
  end

  test "drops tiny noise segments then fillets" do
    line = [
      [ 121.7400, 25.1300 ],
      [ 121.7410, 25.1300 ],
      [ 121.7410001, 25.1300001 ], # ~noise
      [ 121.7415, 25.1305 ],
      [ 121.7415, 25.1315 ]
    ]

    sharpened = Geojson::BusShapeSharpener.sharpen(line)
    junction = [ 121.7415, 25.1300 ]

    nearest = sharpened.min_by { |point| meters_between(point, junction) }
    assert_operator meters_between(nearest, junction), :<, 14.0
    assert_operator sharpened.length, :>=, 4
  end

  test "keeps an already-crisp right angle" do
    line = [
      [ 121.7400, 25.1300 ],
      [ 121.7415, 25.1300 ],
      [ 121.7415, 25.1315 ]
    ]

    sharpened = Geojson::BusShapeSharpener.sharpen(line)

    assert_equal 3, sharpened.length
    assert_in_delta 121.7415, sharpened[1][0], 1e-9
    assert_in_delta 25.1300, sharpened[1][1], 1e-9
  end

  private

  def meters_between(left, right)
    dlon = (right[0] - left[0]) * 111_320 * Math.cos(left[1] * Math::PI / 180.0)
    dlat = (right[1] - left[1]) * 110_540
    Math.hypot(dlon, dlat)
  end

  # Distance from point to the sharp L legs meeting at junction (east then north).
  def distance_to_l_legs(point, junction)
    # Horizontal leg y = junction.lat, x <= junction.lon; vertical leg x = junction.lon, y >= junction.lat
    dx = (point[0] - junction[0]) * 111_320 * Math.cos(junction[1] * Math::PI / 180.0)
    dy = (point[1] - junction[1]) * 110_540
    dist_h = dy.abs
    dist_v = dx.abs
    [ dist_h, dist_v ].min
  end
end
