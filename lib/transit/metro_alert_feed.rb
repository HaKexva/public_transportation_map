# frozen_string_literal: true

module Transit
  class MetroAlertFeed
    FEEDS = [
      { system_id: "taipei_metro", label: "台北捷運", url: "https://www.metro.taipei/News.aspx?n=B7BE39F0EE0C304F" },
      { system_id: "taoyuan_metro", label: "桃園捷運", url: "https://www.tymetro.com.tw/" },
      { system_id: "taichung_metro", label: "台中捷運", url: "https://www.tmrt.com.tw/" },
      { system_id: "kaohsiung_metro", label: "高雄捷運", url: "https://www.krtc.com.tw/" },
      { system_id: "new_taipei_metro", label: "新北捷運", url: "https://www.ntmetro.com.tw/" }
    ].freeze

    def self.call
      # No stable machine-readable outage API across operators. Keep the
      # endpoint + UI ready; return an empty list rather than scraping HTML.
      []
    end
  end
end
