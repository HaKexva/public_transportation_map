# frozen_string_literal: true

module Transit
  module ServiceDayMapper
    WEEKDAY_KEYS = %w[Monday Tuesday Wednesday Thursday Friday].freeze

    module_function

    def calendar_codes(service_day)
      return [] unless service_day.is_a?(Hash)

      codes = []
      codes << "weekday" if weekday?(service_day)
      codes << "saturday" if active?(service_day, "Saturday")
      codes << "sunday" if active?(service_day, "Sunday")
      codes << "holiday" if active?(service_day, "NationalHolidays")
      codes
    end

    def fingerprint(service_day)
      return "unknown" unless service_day.is_a?(Hash)

      (WEEKDAY_KEYS + %w[Saturday Sunday NationalHolidays DayBeforeHoliday DayAfterHoliday TyphoonDay]).map do |key|
        active?(service_day, key) ? "1" : "0"
      end.join
    end

    def calendar_name(service_day)
      codes = calendar_codes(service_day)
      return "營運日" if codes.empty?

      codes.map { |code| ServiceCalendar::COMMON_CODES.fetch(code, code) }.join("、")
    end

    def weekday?(service_day)
      WEEKDAY_KEYS.all? { |key| active?(service_day, key) } &&
        !active?(service_day, "Saturday") &&
        !active?(service_day, "Sunday")
    end

    def active?(service_day, key)
      value = service_day[key]
      return false if value.nil?

      case value
      when true then true
      when false then false
      when Integer then value == 1
      when String
        normalized = value.strip.downcase
        return normalized == "1" || normalized == "true" || normalized == "yes" || normalized == "y"
      else
        # Fallback: try numeric conversion, treating non-numeric values as inactive.
        begin
          value.to_i == 1
        rescue StandardError
          false
        end
      end
    end
  end
end
