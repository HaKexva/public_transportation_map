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

  test "follows the 南門圓環 ring instead of cutting across it" do
    roundabout = Geojson::BusRoundabouts.roundabouts.find { |row|
      Geojson::BusLoopCloser.meters_between(row[:center], [ 121.5149776, 25.0349447 ]) < 5
    }
    assert roundabout, "南門圓環 is missing from the roundabout cache"

    center = roundabout[:center]
    line = [ [ center[0], center[1] + 0.0012 ], center, [ center[0], center[1] - 0.0012 ] ]
    routed = Geojson::BusRoundabouts.through(line, roundabout)

    middle = routed.select { |point| (point[1] - center[1]).abs < 0.00015 }
    assert middle.any?
    assert middle.all? { |point| point[0] < center[0] }
    assert_equal routed, Geojson::BusRoundabouts.through(routed, roundabout)
  end

  test "動物園圓環 stays on the circle past the northwest junction" do
    roundabout = Geojson::BusRoundabouts.roundabouts.find { |row|
      Geojson::BusLoopCloser.meters_between(row[:center], [ 121.5832459, 25.0004076 ]) < 5
    }
    assert roundabout, "動物園圓環 is missing from the roundabout cache"

    line = [
      zoo_at(70, 45),
      zoo_at(90, 22),
      zoo_at(150, 34),
      zoo_at(165, 32),
      zoo_at(-175, 42)
    ]
    routed = Geojson::BusRoundabouts.through(line, roundabout)

    kinked = routed.select { |point|
      radius = zoo_radius(point)
      angle = zoo_angle(point)
      radius.between?(28, 37) && (angle >= 120 || angle <= -170)
    }
    assert_empty kinked
    on_circle = routed.select { |point| zoo_radius(point).between?(21, 26) && zoo_angle(point).between?(110, 170) }
    assert on_circle.length >= 3, "expected the northwest arc, got #{routed.inspect}"
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

  def zoo_at(angle_deg, radius)
    radians = angle_deg * Math::PI / 180.0
    center = Geojson::BusRoundabouts::ZOO_CENTER
    kx = 111_320 * Math.cos(center[1] * Math::PI / 180.0)
    [
      center[0] + (radius * Math.cos(radians) / kx),
      center[1] + (radius * Math.sin(radians) / 110_540)
    ]
  end

  def zoo_radius(point)
    Geojson::BusRoundabouts.zoo_radius(point)
  end

  def zoo_angle(point)
    Geojson::BusRoundabouts.zoo_angle(point)
  end
end
