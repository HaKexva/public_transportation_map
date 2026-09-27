# frozen_string_literal: true

require "test_helper"

class MotionProfileTest < ActiveSupport::TestCase
  test "classifies trip types" do
    assert_equal "hsr", Transit::MotionProfile.kind_for(system_id: "hsr", trip_type: "自由座")
    assert_equal "express", Transit::MotionProfile.kind_for(system_id: "tra", trip_type: "自強")
    assert_equal "local", Transit::MotionProfile.kind_for(system_id: "tra", trip_type: "區間")
    assert_equal "local", Transit::MotionProfile.kind_for(system_id: "taipei_metro", trip_type: nil)
  end

  test "classifies TDX and ODS numeric TRA codes" do
    %w[1 2 3 11 1101 1108].each do |code|
      assert_equal "express", Transit::MotionProfile.kind_for(system_id: "tra", trip_type: code), code
    end
    %w[4 1110 1115].each do |code|
      assert_equal "juguang", Transit::MotionProfile.kind_for(system_id: "tra", trip_type: code), code
    end
    %w[5 6 7 10 1131 1140].each do |code|
      assert_equal "local", Transit::MotionProfile.kind_for(system_id: "tra", trip_type: code), code
    end
  end

  test "unknown types move at constant speed" do
    assert_equal "constant", Transit::MotionProfile.kind_for(system_id: "tra", trip_type: nil)
    assert_equal "constant", Transit::MotionProfile.kind_for(system_id: "sugar_railway", trip_type: "freight")
    assert_in_delta 0.37, Transit::MotionProfile.eased_progress(0.37, kind: "constant"), 1e-9
  end

  test "eased progress stays monotonic between 0 and 1" do
    prev = -0.01
    21.times do |i|
      t = i / 20.0
      value = Transit::MotionProfile.eased_progress(t, kind: "express")
      assert value >= prev - 1e-9
      assert_operator value, :>=, 0.0
      assert_operator value, :<=, 1.0
      prev = value
    end

    assert_in_delta 0.0, Transit::MotionProfile.eased_progress(0, kind: "local")
    assert_in_delta 1.0, Transit::MotionProfile.eased_progress(1, kind: "local")
  end

  test "mid-hop speed is positive for a realistic span" do
    speed = Transit::MotionProfile.speed_kmh(0.5, kind: "local", hop_km: 8.0, hop_minutes: 6.0)
    assert speed > 40
    assert speed < 160
  end
end
