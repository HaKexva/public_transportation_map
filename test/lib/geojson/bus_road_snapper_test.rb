# frozen_string_literal: true

require "test_helper"

class Geojson::BusRoadSnapperTest < ActiveSupport::TestCase
  ORIGIN = [ 121.5000, 25.0000 ].freeze

  # Roads: an east-west street along y = 0 and a north-south street along x = 100.
  class FakeRouter
    def initialize(origin)
      @origin = origin
    end

    def distance_to_road(point)
      x, y = local(point)
      [ y.abs, (x - 100).abs ].min
    end

    def route(from, to)
      [ from, at(100, 0), to ]
    end

    def at(x, y)
      [ @origin[0] + (x / (111_320 * Math.cos(@origin[1] * Math::PI / 180.0))), @origin[1] + (y / 110_540.0) ]
    end

    private

    def local(point)
      [ (point[0] - @origin[0]) * 111_320 * Math.cos(@origin[1] * Math::PI / 180.0), (point[1] - @origin[1]) * 110_540 ]
    end
  end

  setup { @router = FakeRouter.new(ORIGIN) }

  test "re-drives a terminal shortcut across the block along the streets" do
    line = [ @router.at(-400, 0), @router.at(0, 0), @router.at(100, 100) ]
    data = collection(line)

    assert Geojson::BusRoadSnapper.process_collection!(data, router: @router)
    assert_equal [ @router.at(-400, 0), @router.at(0, 0), @router.at(0, 0), @router.at(100, 0), @router.at(100, 100), @router.at(100, 100) ].uniq,
      coordinates(data)
  end

  test "drops a short back-and-forth hook at a line end" do
    line = [ @router.at(-300, 0), @router.at(-20, 0), @router.at(-10, 0), @router.at(-25, 0) ]
    data = collection(line)

    assert Geojson::BusRoadSnapper.process_collection!(data, router: @router)
    assert_equal [ @router.at(-300, 0), @router.at(-25, 0) ], coordinates(data)
  end

  test "joins a terminus whose directions stop short of each other along the streets" do
    arriving = [ @router.at(-1000, 0), @router.at(0, 0) ]
    departing = [ @router.at(100, 200), @router.at(100, 1200) ]
    data = collection(arriving, departing)

    assert Geojson::BusRoadSnapper.process_collection!(data, router: @router)
    assert_equal [ @router.at(-1000, 0), @router.at(0, 0), @router.at(100, 0), @router.at(100, 200) ], coordinates(data)
    assert_equal departing, data["features"].last.dig("geometry", "coordinates")
  end

  test "does not join a terminus with a hairpin" do
    router = Object.new
    def router.distance_to_road(_point) = 0.0
    origin = ORIGIN
    up = FakeRouter.new(origin).at(10, 80)
    router.define_singleton_method(:route) { |from, to| [ from, up, to ] }
    arriving = [ FakeRouter.new(origin).at(0, -1000), FakeRouter.new(origin).at(0, 0) ]
    departing = [ FakeRouter.new(origin).at(20, 0), FakeRouter.new(origin).at(20, -1000) ]

    assert_not Geojson::BusRoadSnapper.process_collection!(collection(arriving, departing), router:)
  end

  test "closes a listed circulator back through its terminus" do
    router = Object.new
    def router.distance_to_road(_point) = 0.0
    via = @router.at(100, 0)
    router.define_singleton_method(:route) { |from, to| [ from, via, to ] }
    loop_line = [ @router.at(200, 0), @router.at(200, 1000), @router.at(0, 1000), @router.at(0, 0) ]
    data = collection(loop_line).merge("properties" => { "id" => "new_taipei_177_47105ddaf0" })

    assert Geojson::BusRoadSnapper.process_collection!(data, router:)
    assert_equal [ @router.at(0, 0), via, *loop_line ], coordinates(data)

    unlisted = collection(loop_line).merge("properties" => { "id" => "new_taipei_999" })
    assert_not Geojson::BusRoadSnapper.process_collection!(unlisted, router:)
  end

  test "leaves on-road lines and stretches far from termini alone" do
    on_road = [ @router.at(-2000, 0), @router.at(-1000, 0), @router.at(0, 0) ]
    assert_not Geojson::BusRoadSnapper.process_collection!(collection(on_road), router: @router)

    # Off-road, but more than END_ZONE_METERS from either end and no hub stop.
    far = [ @router.at(-2000, 0), @router.at(-1000, 0), @router.at(-940, 60), @router.at(-880, 0), @router.at(0, 0) ]
    assert_not Geojson::BusRoadSnapper.process_collection!(collection(far), router: @router)
  end

  private

  def collection(*lines)
    { "type" => "FeatureCollection", "features" => lines.each_with_index.map { |line, direction|
      { "type" => "Feature", "properties" => { "feature_type" => "route", "direction" => direction },
        "geometry" => { "type" => "LineString", "coordinates" => line } }
    } }
  end

  def coordinates(data)
    data["features"].first.dig("geometry", "coordinates")
  end
end
