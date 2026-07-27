# frozen_string_literal: true

module Transit
  # Resolves which `service_calendars` (by `code`) should be used for a given date.
  #
  # For TDX-imported datasets, the importer stores calendars as `sd_<fingerprint>`.
  # Fingerprint bit order matches `Transit::ServiceDayMapper`:
  # Monday Tuesday Wednesday Thursday Friday Saturday Sunday
  # NationalHolidays DayBeforeHoliday DayAfterHoliday TyphoonDay
  #
  # We match any `sd_` calendar whose weekday bit is set for the requested date,
  # plus simple codes (`weekday` / `saturday` / `sunday` / `daily`).
  module ServiceCalendarResolver
    module_function

    WEEKDAY_BIT_INDEX = {
      1 => 0, # Monday
      2 => 1,
      3 => 2,
      4 => 3,
      5 => 4,
      6 => 5, # Saturday
      0 => 6  # Sunday
    }.freeze

    # Builds a service_day hash compatible with `Transit::ServiceDayMapper`.
    def service_day_for_date(date)
      day = date.wday # 0=Sunday..6=Saturday

      {
        # TDX weekday service types set Mon..Fri all true.
        "Monday" => (1..5).include?(day),
        "Tuesday" => (1..5).include?(day),
        "Wednesday" => (1..5).include?(day),
        "Thursday" => (1..5).include?(day),
        "Friday" => (1..5).include?(day),
        "Saturday" => day == 6,
        "Sunday" => day == 0,
        "NationalHolidays" => false,
        "DayBeforeHoliday" => false,
        "DayAfterHoliday" => false,
        "TyphoonDay" => false
      }
    end

    def weekday_bit_index(date)
      WEEKDAY_BIT_INDEX.fetch(date.wday)
    end

    def weekday_simple_code_for_date(date)
      day = date.wday
      return "saturday" if day == 6
      return "sunday" if day == 0

      "weekday"
    end

    def simple_codes_for_date(date)
      [ weekday_simple_code_for_date(date), "daily" ]
    end

    # Exact fingerprint for the date's weekday service type (useful for tests / debugging).
    def calendar_codes_for_date(date)
      fingerprint_code = "sd_#{ServiceDayMapper.fingerprint(service_day_for_date(date))}"
      ([ fingerprint_code ] + simple_codes_for_date(date)).compact.uniq
    end

    def fingerprint_matches_date?(code, date)
      return false unless code.to_s.start_with?("sd_")

      bits = code.to_s.delete_prefix("sd_")
      bit = weekday_bit_index(date)
      return false if bits.length <= bit

      bits[bit] == "1"
    end

    # Returns service_calendar ids across all datasets for the given date.
    def calendar_ids_for_date(date)
      simple = simple_codes_for_date(date)
      bit = weekday_bit_index(date)

      ids = ServiceCalendar.where(code: simple).pluck(:id)
      ServiceCalendar.where("code LIKE 'sd_%'").find_each do |calendar|
        ids << calendar.id if fingerprint_matches_date?(calendar.code, date)
      end
      ids.uniq
    end

    # Returns service_calendar ids for the given dataset/date.
    def calendar_ids_for(dataset:, date:)
      simple = simple_codes_for_date(date)
      ids = dataset.service_calendars.where(code: simple).pluck(:id)
      dataset.service_calendars.where("code LIKE 'sd_%'").find_each do |calendar|
        ids << calendar.id if fingerprint_matches_date?(calendar.code, date)
      end
      ids.uniq
    end
  end
end
