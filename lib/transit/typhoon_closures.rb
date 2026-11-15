# frozen_string_literal: true

require "net/http"
require "uri"

module Transit
  # Dates when a county has stopped work for a natural disaster (颱風假).
  # Only that date is returned. The days before and after stay on the weekly timetable.
  class TyphoonClosures
    class Error < StandardError; end

    URL = "https://www.dgpa.gov.tw/typh/daily/nds.html"
    USER_AGENT = "public-transportation-map/1.0"
    ROW = %r{<FONT>(?<city>[^<]+)</FONT>\s*</TD>\s*<TD[^>]*>\s*<FONT[^>]*>(?<status>[^<]*)</FONT>}m
    WORK_STOP = /停止上班/
    NOT_WORK_STOP = /未達停止上班|照常上班/

    def self.dates(http_get: nil, today: Time.zone.today)
      new(http_get:, today:).dates
    end

    def self.closed?(date, http_get: nil, today: Time.zone.today)
      dates(http_get:, today:).include?(date)
    end

    def initialize(http_get: nil, today: Time.zone.today)
      @http_get = http_get
      @today = today
    end

    def dates
      return [] if Rails.env.test? && @http_get.nil?

      found = []
      html.scan(ROW) do
        city = Regexp.last_match[:city].to_s.strip
        status = Regexp.last_match[:status].to_s.strip
        next if city.blank? || city.end_with?("地區")
        next unless status.match?(WORK_STOP) && !status.match?(NOT_WORK_STOP)

        found << day_for(status)
      end
      found.uniq.sort
    rescue Error, SocketError, SystemCallError, Timeout::Error => error
      Rails.logger.error("[TyphoonClosures] #{error.class}: #{error.message}")
      []
    end

    private

    def day_for(status)
      return @today + 1 if status.include?("明天")
      return @today + 2 if status.include?("後天")

      @today
    end

    def html
      return @http_get.call(URL) if @http_get

      uri = URI(URL)
      request = Net::HTTP::Get.new(uri)
      request["User-Agent"] = USER_AGENT
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 20) do |http|
        http.request(request)
      end
      raise Error, "DGPA #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      response.body.dup.force_encoding(Encoding::UTF_8)
    end
  end
end
