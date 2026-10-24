# frozen_string_literal: true

require "test_helper"

class GeojsonBusShapeTrimmerTest < ActiveSupport::TestCase
  # ~2.2 km east-west street, driven out and back.
  OUT = (0..20).map { |i| [ 121.50 + (i * 0.001), 25.0 ] }.freeze
  BACK = OUT.reverse.map { |lon, lat| [ lon, lat + 0.0002 ] }.freeze

  test "trims a round-trip shape to the one-way stop span" do
    stops = [ OUT.first, OUT[10], OUT.last ]
    trimmed = Geojson::BusShapeTrimmer.trim_to_stops(OUT + BACK, stops)

    assert_in_delta Geojson::BusShapeTrimmer.path_length(OUT), Geojson::BusShapeTrimmer.path_length(trimmed), 5.0
    assert_in_delta OUT.last[0], trimmed.last[0], 1e-6
  end

  test "keeps the terminus turnaround up to the opposite direction's first stop" do
    stops = [ OUT.first, OUT[10], OUT[18] ]
    trimmed = Geojson::BusShapeTrimmer.trim_to_stops(OUT + BACK, stops, end_point: BACK[1])

    assert_in_delta BACK[1][0], trimmed.last[0], 1e-6
    assert_in_delta BACK[1][1], trimmed.last[1], 1e-6
  end

  test "trims a closed round trip even when a trailing terminal loop is missing from the shape" do
    detached = (0..3).map { |i| [ 121.50 + (i * 0.001), 25.01 ] }
    stops = [ OUT.first, OUT[5], OUT[10], OUT[15], OUT[18], OUT.last ] + detached.first(1)
    trimmed = Geojson::BusShapeTrimmer.trim_to_stops(OUT + BACK, stops, end_point: BACK[1])

    assert_in_delta BACK[1][0], trimmed.last[0], 1e-6
    assert_operator Geojson::BusShapeTrimmer.path_length(trimmed), :<, Geojson::BusShapeTrimmer.path_length(OUT) + 200
  end

  test "restores the stretch linking a trimmed end to the other direction's start" do
    outbound = OUT[0..10]
    inbound = BACK[12..]
    restored_out, restored_in = Geojson::BusShapeTrimmer.restore_handoffs([ outbound, inbound ], [ OUT + BACK, BACK ])

    assert_equal outbound, restored_out
    assert_equal outbound.last, restored_in.first
    assert_equal inbound.last, restored_in.last
  end

  test "leaves shapes that already match their stops alone" do
    stops = [ OUT.first, OUT.last ]

    assert_equal OUT, Geojson::BusShapeTrimmer.trim_to_stops(OUT, stops)
  end

  test "leaves shapes that run against the stop order alone" do
    stops = [ OUT.first, OUT[10], OUT.last ]
    line = BACK + OUT.map { |lon, lat| [ lon, lat + 0.01 ] }

    assert_equal line, Geojson::BusShapeTrimmer.trim_to_stops(line, stops)
  end

  test "joins nearly-meeting termini of both directions" do
    outbound = OUT[0..-2]
    inbound = BACK

    joined_out, joined_in = Geojson::BusShapeTrimmer.join_termini(outbound, inbound)

    assert_equal inbound.first, joined_out.last
    assert_equal outbound.first, joined_in.last
  end

  test "starts the other direction at a dead-end terminus instead of hooking back" do
    outbound = OUT
    inbound = BACK.drop(1)

    joined_out, joined_in = Geojson::BusShapeTrimmer.join_termini(outbound, inbound)

    assert_equal outbound.last, joined_out.last
    assert_equal outbound.last, joined_in.first
    assert_equal inbound, joined_in.drop(1).first(inbound.length)
  end
end
