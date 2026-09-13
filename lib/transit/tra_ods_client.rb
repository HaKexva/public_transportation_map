# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module Transit
  # Fetches TRA daily timetables from 台鐵 ODS (no API key).
  class TraOdsClient
    class Error < StandardError; end

    LIST_URL = "https://ods.railway.gov.tw/tra-ods-web/ods/download/dataResource/railway_schedule/JSON/list"
    SCHEDULE_URL_TEMPLATE = "https://ods.railway.gov.tw/tra-ods-web/ods/download/dataResource/exceptionDataResource/%s"
    STATIONS_URL = "https://ods.railway.gov.tw/tra-ods-web/ods/download/dataResource/0518b833e8964d53bfea3f7691aea0ee"
    USER_AGENT = "public-transportation-map/1.0"
    DEFAULT_DAYS = 14
    MIN_DAYS = 7

    def initialize(http_get: nil)
      @http_get = http_get
    end

    def fetch_daily_timetables(from_date: Date.current, days: DEFAULT_DAYS, min_days: MIN_DAYS)
      by_date = parse_list_page(http_get(LIST_URL))
      selected = pick_days(by_date, from_date, days)
      if selected.length < min_days
        raise Error, "ODS list published #{selected.length} days from #{from_date} (need ≥#{min_days})"
      end

      stations = fetch_station_index
      selected.map do |date_str, resource_id|
        payload = JSON.parse(http_get(format(SCHEDULE_URL_TEMPLATE, resource_id)))
        {
          date: Date.iso8601("#{date_str[0, 4]}-#{date_str[4, 2]}-#{date_str[6, 2]}"),
          trains: normalize_trains(payload, stations)
        }
      end
    end

    private

    def fetch_station_index
      payload = JSON.parse(http_get(STATIONS_URL))
      Array(payload).each_with_object({}) do |row, index|
        code = row["stationCode"].to_s
        next if code.blank?

        index[code] = row["stationName"].to_s
      end
    end

    def parse_list_page(html)
      rows = html.to_s.scan(%r{exceptionDataResource/([0-9a-f]+)">(\d{8})\.json}i)
      raise Error, "ODS list page had no daily JSON links" if rows.empty?

      rows.each_with_object({}) { |(resource_id, date_str), hash| hash[date_str] = resource_id }
    end

    def pick_days(by_date, start_date, days)
      (0...days).filter_map do |offset|
        date_str = (start_date + offset).strftime("%Y%m%d")
        next unless by_date.key?(date_str)

        [ date_str, by_date[date_str] ]
      end
    end

    def normalize_trains(payload, stations)
      infos = payload["TrainInfos"] || payload["TrainTimetables"] || []
      Array(infos).filter_map do |train|
        nested = train["TrainInfo"] || train
        train_no = nested["Train"].presence || nested["TrainNo"].presence
        time_infos = train["TimeInfos"] || nested["TimeInfos"] || train["StopTimes"] || nested["StopTimes"]
        next if train_no.blank? || time_infos.blank?

        stop_times = Array(time_infos).filter_map do |stop|
          code = (stop["Station"] || stop["StationID"]).to_s
          next if code.blank?

          {
            "StationID" => code,
            "StationName" => { "Zh_tw" => stations[code].presence || stop.dig("StationName", "Zh_tw") },
            "ArrivalTime" => stop["ARRTime"] || stop["ArrivalTime"],
            "DepartureTime" => stop["DEPTime"] || stop["DepartureTime"]
          }
        end
        next if stop_times.length < 2

        {
          "TrainInfo" => {
            "TrainNo" => train_no.to_s,
            "Direction" => nested["LineDir"] || nested["Direction"] || 0,
            "TrainTypeCode" => nested["CarClass"] || nested["Type"] || nested["TrainTypeCode"],
            "TripHeadSign" => nested["TripHeadSign"].presence || stop_times.last.dig("StationName", "Zh_tw"),
            "Note" => nested["Note"].to_s
          },
          "StopTimes" => stop_times
        }
      end
    end

    def http_get(url)
      return @http_get.call(url) if @http_get

      uri = URI(url)
      request = Net::HTTP::Get.new(uri)
      request["User-Agent"] = USER_AGENT
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 20, read_timeout: 120) do |http|
        http.request(request)
      end
      unless response.is_a?(Net::HTTPSuccess)
        raise Error, "ODS #{response.code} for #{url}"
      end

      response.body
    end
  end
end
