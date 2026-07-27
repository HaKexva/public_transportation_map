# frozen_string_literal: true

require "test_helper"

class SyntheticDelayTest < ActiveSupport::TestCase
  test "status_for returns on_time for small absolute delay" do
    assert_equal "on_time", Transit::SyntheticDelay.status_for(0)
    assert_equal "on_time", Transit::SyntheticDelay.status_for(60)
    assert_equal "on_time", Transit::SyntheticDelay.status_for(-60)
    assert_equal "on_time", Transit::SyntheticDelay.status_for(119)
    assert_equal "on_time", Transit::SyntheticDelay.status_for(-119)
  end

  test "status_for returns delayed for positive delay >= 120 seconds" do
    assert_equal "delayed", Transit::SyntheticDelay.status_for(120)
    assert_equal "delayed", Transit::SyntheticDelay.status_for(600)
  end

  test "status_for returns early for negative delay <= -120 seconds" do
    assert_equal "early", Transit::SyntheticDelay.status_for(-120)
    assert_equal "early", Transit::SyntheticDelay.status_for(-300)
  end

  test "delay_seconds_for_key is deterministic for same key+day" do
    at = Time.zone.parse("2026-07-27T10:00:00+08:00")
    a = Transit::SyntheticDelay.delay_seconds_for_key("trip:123", at: at)
    b = Transit::SyntheticDelay.delay_seconds_for_key("trip:123", at: at)
    assert_equal a, b
  end

  test "delay_seconds_for_key differs for different keys" do
    at = Time.zone.parse("2026-07-27T10:00:00+08:00")
    a = Transit::SyntheticDelay.delay_seconds_for_key("trip:1", at: at)
    b = Transit::SyntheticDelay.delay_seconds_for_key("trip:2", at: at)
    # Different keys should (with overwhelming probability) produce different delays
    assert_not_equal a, b
  end

  test "delay_seconds_for_headway returns integer in expected range" do
    at = Time.zone.parse("2026-07-27T10:00:00+08:00")
    d = Transit::SyntheticDelay.delay_seconds_for_headway(route_id: "bannan", direction: "outbound", at: at)
    assert_kind_of Numeric, d
    assert d >= -300
    assert d <= 660
  end
end
