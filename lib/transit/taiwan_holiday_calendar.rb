# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module Transit
  # Official days off from the Taiwan government calendar.
  # A 連假 is the consecutive run of days off that contains a named holiday.
  # The workdays on either side are not part of it.
  class TaiwanHolidayCalendar
    class Error < StandardError; end

    Record = Data.define(:date, :holiday, :name)
    URL = "https://cdn.jsdelivr.net/gh/ruyut/TaiwanCalendar/data/%d.json"
    WEEKEND_NAME = /\A星期/

    class << self
      attr_accessor :records

      def long_weekend?(date)
        new.long_weekend?(date)
      end
    end

    def initialize(http_get: nil)
      @http_get = http_get
      @by_date = {}
    end

    def long_weekend?(date)
      long_weekend_dates(from: date, to: date).include?(date)
    end

    def long_weekend_dates(from:, to:)
      named = (from..to).select { |date| named_holiday?(date) }
      return [] if named.empty?

      covered = {}
      named.each do |date|
        expand_block(date).each do |day|
          covered[day] = true if day >= from && day <= to
        end
      end
      covered.keys.sort
    end

    def named_holiday?(date)
      record = record_for(date)
      return false unless record&.holiday

      name = record.name.to_s.strip
      name.present? && !WEEKEND_NAME.match?(name)
    end

    def day_off?(date)
      record_for(date)&.holiday == true
    end

    private

    def expand_block(date)
      days = [ date ]
      day = date - 1
      while day_off?(day)
        days.unshift(day)
        day -= 1
      end
      day = date + 1
      while day_off?(day)
        days.push(day)
        day += 1
      end
      days
    end

    def record_for(date)
      year_records(date.year)[date]
    end

    def year_records(year)
      return @by_date[year] if @by_date.key?(year)

      rows = if self.class.records
        self.class.records.select { |record| record.date.year == year }
      elsif Rails.env.test?
        []
      else
        fetch_year(year)
      end
      @by_date[year] = rows.index_by(&:date)
    end

    def fetch_year(year)
      Rails.cache.fetch("taiwan_holidays/#{year}", expires_in: 12.hours) do
        payload = JSON.parse(http_get(format(URL, year)))
        self.class.parse(payload)
      end
    rescue Error, JSON::ParserError, SocketError, SystemCallError, Timeout::Error => error
      Rails.logger.error("[TaiwanHolidayCalendar] #{year}: #{error.class}: #{error.message}")
      []
    end

    def http_get(url)
      return @http_get.call(url) if @http_get

      uri = URI(url)
      request = Net::HTTP::Get.new(uri)
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 10, read_timeout: 20) do |http|
        http.request(request)
      end
      raise Error, "holiday calendar #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      response.body
    end

    class << self
      def parse(rows)
        Array(rows).filter_map do |row|
          text = row["date"].to_s
          next if text.blank?

          Record.new(date: Date.strptime(text, "%Y%m%d"), holiday: row["isHoliday"] == true, name: row["description"].to_s)
        end
      end
    end
  end
end
