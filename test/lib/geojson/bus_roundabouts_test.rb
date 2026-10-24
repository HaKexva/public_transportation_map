# frozen_string_literal: true

require "test_helper"

class Geojson::BusRoundaboutsTest < ActiveSupport::TestCase
  CENTER = [ 121.5, 25.0 ].freeze

  test "routes a pass-through along the ring counter-clockwise" do
    roundabout = roundabout_of(radius: 20.0)
    line = [ offset(-200, 0), offset(-5, 0), offset(5, 0), offset(200, 0) ]

    routed = Geojson::BusRoundabouts.through(line, roundabout)

    assert_equal line.first, routed.first
    assert_equal line.last, routed.last
    ring = routed.select { |point| distance(point).between?(19.0, 21.0) }
    assert ring.length >= 5, "expected the ring to be followed, got #{routed.inspect}"
    # Eastbound, right-hand traffic keeps to the south half.
    assert ring.all? { |point| point[1] <= CENTER[1] + 1e-7 }
    assert_equal routed, Geojson::BusRoundabouts.through(routed, roundabout)
  end

  test "leaves lines that only pass nearby alone" do
    roundabout = roundabout_of(radius: 20.0)
    line = [ offset(-200, 35), offset(200, 35) ]

    assert_same line, Geojson::BusRoundabouts.through(line, roundabout)
  end

  private

  def roundabout_of(radius:)
    ring = (0...16).map { |step| offset(radius * Math.cos(step * Math::PI / 8), radius * Math.sin(step * Math::PI / 8)) }
    reach = radius + [ 15.0, radius * 0.5 ].max
    { center: CENTER, radius:, reach:, ring:, bbox: [ 0, 0, 180, 90 ] }
  end

  def offset(east, north)
    [ CENTER[0] + (east / (111_320 * Math.cos(CENTER[1] * Math::PI / 180))), CENTER[1] + (north / 110_540.0) ]
  end

  def distance(point)
    Geojson::BusLoopCloser.meters_between(point, CENTER)
  end
end
