# frozen_string_literal: true

require "test_helper"

class ServiceCalendarResolverTest < ActiveSupport::TestCase
  test "service_day_for_date weekday sets Mon-Fri true, Sat/Sun false" do
    monday = Date.new(2026, 7, 27)
    day = Transit::ServiceCalendarResolver.service_day_for_date(monday)

    assert day["Monday"]
    assert day["Tuesday"]
    assert day["Friday"]
    refute day["Saturday"]
    refute day["Sunday"]
  end

  test "service_day_for_date Saturday sets Sat true, weekdays false" do
    saturday = Date.new(2026, 7, 25)
    day = Transit::ServiceCalendarResolver.service_day_for_date(saturday)

    assert day["Saturday"]
    refute day["Monday"]
    refute day["Sunday"]
  end

  test "fingerprint_matches_date? matches weekday bit for Monday" do
    monday = Date.new(2026, 7, 27) # wday=1 => bit index 0
    # sd_11111000000: Mon-Fri set (bits 0-4 are '1')
    assert Transit::ServiceCalendarResolver.fingerprint_matches_date?("sd_11111000000", monday)
    # sd_00000110000: Sat+Sun set (bits 5-6 are '1')
    refute Transit::ServiceCalendarResolver.fingerprint_matches_date?("sd_00000110000", monday)
  end

  test "fingerprint_matches_date? returns false for non-sd_ codes" do
    refute Transit::ServiceCalendarResolver.fingerprint_matches_date?("weekday", Date.today)
    refute Transit::ServiceCalendarResolver.fingerprint_matches_date?("", Date.today)
  end

  test "fingerprint_matches_date? matches Saturday bit" do
    saturday = Date.new(2026, 7, 25) # wday=6 => bit index 5
    assert Transit::ServiceCalendarResolver.fingerprint_matches_date?("sd_00000110000", saturday)
    refute Transit::ServiceCalendarResolver.fingerprint_matches_date?("sd_11111000000", saturday)
  end

  test "fingerprint_matches_date? matches Sunday bit" do
    sunday = Date.new(2026, 7, 26) # wday=0 => bit index 6
    assert Transit::ServiceCalendarResolver.fingerprint_matches_date?("sd_11111110000", sunday)
    assert Transit::ServiceCalendarResolver.fingerprint_matches_date?("sd_00000010000", sunday)
    refute Transit::ServiceCalendarResolver.fingerprint_matches_date?("sd_11111000000", sunday)
  end

  test "simple_codes_for_date returns 'weekday' on Monday" do
    codes = Transit::ServiceCalendarResolver.simple_codes_for_date(Date.new(2026, 7, 27))
    assert_includes codes, "weekday"
    assert_includes codes, "daily"
  end

  test "simple_codes_for_date returns 'saturday' on Saturday" do
    codes = Transit::ServiceCalendarResolver.simple_codes_for_date(Date.new(2026, 7, 25))
    assert_includes codes, "saturday"
  end

  test "calendar_codes_for_date includes exact fingerprint" do
    monday = Date.new(2026, 7, 27)
    codes = Transit::ServiceCalendarResolver.calendar_codes_for_date(monday)
    assert_includes codes, "sd_11111000000"
  end
end
