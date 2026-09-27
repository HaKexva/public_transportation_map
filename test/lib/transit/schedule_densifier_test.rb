# frozen_string_literal: true

require "test_helper"

class ScheduleDensifierTest < ActiveSupport::TestCase
  setup do
    @route = TransitRoute.create!(
      system_id: "tra",
      route_id: "test_densify_line",
      name: "測試密化線",
      line_ref: "TD"
    )
    %w[A B C D E].each_with_index do |ref, index|
      TransitRouteStation.create!(
        transit_route: @route,
        station_ref: ref,
        name: ref,
        stop_sequence: index + 1,
        direction: TransitRoute::DIRECTION_BOTH
      )
    end
    @densifier = Transit::ScheduleDensifier.new
  end

  test "inserts through stations between booked express stops" do
    stops = [
      { station_ref: "A", arrival: 600.0, departure: 601.0 },
      { station_ref: "E", arrival: 640.0, departure: 641.0 }
    ]

    result = @densifier.densify(@route, stops)
    refs = result.map { |stop| stop[:station_ref] }

    assert_equal %w[A B C D E], refs
    assert result[1][:through]
    assert result[2][:through]
    assert result[3][:through]
    refute result[0][:through]
    refute result[-1][:through]
    assert_in_delta 610.75, result[1][:arrival], 0.2
    assert_equal result[1][:arrival], result[1][:departure]
  end

  test "spaces through-station pass times by distance" do
    # A..E on one meridian; B sits 1 km from A, the rest are 3 km apart.
    lat_per_km = 1.0 / 111.195
    coords = { "A" => 0.0, "B" => 1.0, "C" => 4.0, "D" => 7.0, "E" => 10.0 }
      .transform_values { |km| [ 24.0 + (km * lat_per_km), 121.0 ] }
    stops = [
      { station_ref: "A", arrival: 600.0, departure: 600.0 },
      { station_ref: "E", arrival: 640.0, departure: 640.0 }
    ]

    densifier = Transit::ScheduleDensifier.new(coord_lookup: ->(_route, ref) { coords[ref] })
    result = densifier.densify(@route, stops)

    assert_in_delta 604.0, result[1][:arrival], 0.05
    assert_in_delta 616.0, result[2][:arrival], 0.05
    assert_in_delta 628.0, result[3][:arrival], 0.05
  end

  test "leaves already-dense local trips unchanged" do
    stops = [
      { station_ref: "A", arrival: 600.0, departure: 601.0 },
      { station_ref: "B", arrival: 610.0, departure: 611.0 },
      { station_ref: "C", arrival: 620.0, departure: 621.0 }
    ]

    result = @densifier.densify(@route, stops)
    assert_equal %w[A B C], result.map { |stop| stop[:station_ref] }
    assert result.none? { |stop| stop[:through] }
  end
end
