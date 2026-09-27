# frozen_string_literal: true

module Transit
  # Operator service alerts from TDX Rail/Metro/Alert. TDX has no 新北捷運
  # (NTMC) feed, so that operator is omitted rather than scraped.
  class MetroAlertFeed
    CACHE_KEY = "metro_alert_feed/v1"
    CACHE_TTL = 2.minutes
    NORMAL_STATUS = 1
    NORMAL_TITLE = "正常營運"

    OPERATORS = [
      { code: "TRTC", system_id: "taipei_metro", label: "台北捷運", url: "https://www.metro.taipei/" },
      { code: "TYMC", system_id: "taoyuan_metro", label: "桃園捷運", url: "https://www.tymetro.com.tw/" },
      { code: "TMRT", system_id: "taichung_metro", label: "台中捷運", url: "https://www.tmrt.com.tw/" },
      { code: "KRTC", system_id: "kaohsiung_metro", label: "高雄捷運", url: "https://www.krtc.com.tw/" },
      { code: "KLRT", system_id: "kaohsiung_metro", label: "高雄輕軌", url: "https://www.krtc.com.tw/" }
    ].freeze

    def self.call(client: nil, cache: Rails.cache)
      new(client: client, cache: cache).call
    end

    def initialize(client: nil, cache: Rails.cache)
      @client = client || Transit::TdxClient.new
      @cache = cache
    end

    def call
      return [] unless @client.configured?

      @cache.fetch(CACHE_KEY, expires_in: CACHE_TTL, race_condition_ttl: 30.seconds) { fetch_alerts }
    end

    private

    def fetch_alerts
      OPERATORS.flat_map { |operator| operator_alerts(operator) }
    end

    def operator_alerts(operator)
      payload = @client.get_json("v2/Rail/Metro/Alert/#{operator[:code]}", query: { "$format" => "JSON" })
      Array(payload.is_a?(Hash) ? payload["Alerts"] : payload).filter_map { |alert| serialize(alert, operator) }
    rescue Transit::TdxClient::Error, JSON::ParserError, SocketError, Timeout::Error, SystemCallError => error
      Rails.logger.warn("metro alert feed #{operator[:code]} failed: #{error.message}")
      []
    end

    def serialize(alert, operator)
      return nil unless alert.is_a?(Hash)

      title = alert["Title"].to_s.strip
      return nil if alert["Status"].to_i == NORMAL_STATUS || title.empty? || title == NORMAL_TITLE

      description = alert["Description"].to_s.strip
      {
        id: "#{operator[:code]}:#{alert['AlertID']}",
        system_id: operator[:system_id],
        operator: operator[:label],
        title: title,
        message: description == title ? nil : description.presence,
        lines: Array(alert.dig("Scope", "Lines")).filter_map { |line| line["LineID"].presence },
        url: alert["AlertURL"].presence || operator[:url],
        published_at: alert["PublishTime"]
      }
    end
  end
end
