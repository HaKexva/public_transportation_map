# frozen_string_literal: true

require "test_helper"

class TaiwanHolidayCalendarTest < ActiveSupport::TestCase
  Record = Transit::TaiwanHolidayCalendar::Record

  setup do
    Transit::TaiwanHolidayCalendar.records = [
      rec("2026-02-13", false, ""),
      rec("2026-02-14", true, ""),
      rec("2026-02-15", true, "小年夜"),
      rec("2026-02-16", true, "農曆除夕"),
      rec("2026-02-20", true, "補假"),
      rec("2026-02-21", true, ""),
      rec("2026-02-22", true, ""),
      rec("2026-02-23", false, ""),
      rec("2026-02-26", false, ""),
      rec("2026-02-27", true, "補假"),
      rec("2026-02-28", true, "和平紀念日"),
      rec("2026-03-01", true, ""),
      rec("2026-03-02", false, "")
    ]
    @calendar = Transit::TaiwanHolidayCalendar.new
  end

  teardown do
    Transit::TaiwanHolidayCalendar.records = nil
  end

  test "a long weekend includes the days off around a named holiday and stops at workdays" do
    dates = @calendar.long_weekend_dates(from: Date.new(2026, 2, 1), to: Date.new(2026, 3, 5))

    assert_includes dates, Date.new(2026, 2, 14)
    assert_includes dates, Date.new(2026, 2, 22)
    assert_includes dates, Date.new(2026, 2, 27)
    assert_includes dates, Date.new(2026, 3, 1)
    refute_includes dates, Date.new(2026, 2, 13)
    refute_includes dates, Date.new(2026, 2, 23)
    refute_includes dates, Date.new(2026, 2, 26)
    refute_includes dates, Date.new(2026, 3, 2)
  end

  private

  def rec(date, holiday, name)
    Record.new(date: Date.iso8601(date), holiday: holiday, name: name)
  end
end
