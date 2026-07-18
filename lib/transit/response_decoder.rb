# frozen_string_literal: true

module Transit
  # TDX wraps list payloads differently across API versions.
  module ResponseDecoder
    LIST_KEYS = %w[
      value
      TrainTimetables
      GeneralTimetables
      GeneralTimetable
      Frequencies
      StationTimeTables
    ].freeze

    module_function

    def list(payload)
      return payload if payload.is_a?(Array)
      return [] unless payload.is_a?(Hash)

      LIST_KEYS.each do |key|
        value = payload[key]
        return value if value.is_a?(Array)
      end

      payload.values.find { |value| value.is_a?(Array) } || []
    end

    def localized_name(value)
      case value
      when Hash
        value["Zh_tw"].presence || value["zh_tw"].presence || value["Zh"].presence || value.values.find { |v| v.is_a?(String) }
      else
        value.to_s.presence
      end
    end
  end
end
