# frozen_string_literal: true

require "test_helper"

class VehiclePositionQueryTest < ActiveSupport::TestCase
  # These tests depend on schedule data seeded via `rails db:seed` or TDX import.
  # They are skipped when the DB has no schedule data.

  def self.has_schedule_data?
    TransitRoute.where(route_id: "bannan").exists? &&
      ServiceCalendar.exists?
  end

  setup do
    skip "No schedule data in test DB – run rails db:seed first" unless self.class.has_schedule_data?
    @at = Time.new(2026, 7, 27, 10, 0, 0, "+08:00").in_time_zone("Asia/Taipei")
  end

  test "returns empty array when route_ids is empty" do
    result = Transit::VehiclePositionQuery.new(at: @at, route_ids: []).call
    assert_equal [], result
  end

  test "returns empty array for unknown route_id" do
    result = Transit::VehiclePositionQuery.new(at: @at, route_ids: [ "nonexistent_xyz" ]).call
    assert_equal [], result
  end

  test "returns vehicles for bannan route during service hours" do
    result = Transit::VehiclePositionQuery.new(at: @at, route_ids: [ "bannan" ]).call
    assert result.length >= 1, "Expected at least 1 vehicle on bannan at 10:00"

    vehicle = result.first
    assert_includes %w[on_time delayed early], vehicle[:status]
    assert_kind_of Numeric, vehicle[:progress]
    assert vehicle[:progress] >= 0 && vehicle[:progress] <= 1
    assert vehicle[:from_station_ref].present?
    assert vehicle[:to_station_ref].present?
    assert_equal "bannan", vehicle[:route_id]
    assert_equal "taipei_metro", vehicle[:system_id]
  end

  test "returns vehicles for TRA western_trunk_north" do
    result = Transit::VehiclePositionQuery.new(at: @at, route_ids: [ "western_trunk_north" ]).call
    assert result.length >= 1, "Expected TRA trains at 10:00 weekday"

    vehicle = result.first
    assert_includes %w[on_time delayed early], vehicle[:status]
    assert vehicle[:train_number].present?
  end

  test "vehicle hash contains required keys" do
    result = Transit::VehiclePositionQuery.new(at: @at, route_ids: [ "bannan" ]).call
    skip "No vehicles returned" if result.empty?

    vehicle = result.first
    %i[id route_id system_id from_station_ref to_station_ref progress delay_seconds status].each do |key|
      assert vehicle.key?(key), "Missing key #{key}"
    end
  end

  test "returns vehicles from multiple systems in one call" do
    result = Transit::VehiclePositionQuery.new(
      at: @at,
      route_ids: %w[bannan western_trunk_north taiwan_hsr]
    ).call

    route_ids = result.map { |v| v[:route_id] }.uniq
    assert route_ids.length >= 2, "Expected vehicles from at least 2 different routes"
  end

  test "does not exceed hard cap of 200 vehicles" do
    result = Transit::VehiclePositionQuery.new(at: @at, route_ids: %w[bannan western_trunk_north taiwan_hsr]).call
    assert result.length <= 200
  end

  test "progress is within 0..1 for all returned vehicles" do
    result = Transit::VehiclePositionQuery.new(at: @at, route_ids: %w[bannan western_trunk_north]).call
    result.each do |v|
      assert v[:progress] >= 0 && v[:progress] <= 1,
             "progress #{v[:progress]} out of bounds for #{v[:id]}"
    end
  end

  test "does not raise for night time query" do
    night_at = Time.new(2026, 7, 27, 3, 0, 0, "+08:00").in_time_zone("Asia/Taipei")
    result = Transit::VehiclePositionQuery.new(at: night_at, route_ids: [ "western_trunk_north" ]).call
    assert_kind_of Array, result
  end
end
