# frozen_string_literal: true

module Geojson
  module TraStationCatalog
    CACHE_PATH = Rails.root.join("lib/geojson/cache/tra_stations.json").freeze

    EXCLUDED_REFS_BY_LINE = {
      "western_trunk_north" => %w[3431],
      "western_trunk_south" => %w[3431],
      "mountain_line" => %w[3431],
      "sea_line" => %w[3431]
    }.freeze

    TAIDONG_SOUTHERN_FALLBACK_STATIONS = [
      { ref: "6010", name: "山里", lon: 121.069722, lat: 22.897222 },
      { ref: "6020", name: "鹿野", lon: 121.1275, lat: 22.951389 },
      { ref: "6030", name: "瑞源", lon: 121.150833, lat: 22.982778 },
      { ref: "6040", name: "瑞和", lon: 121.160556, lat: 23.004167 },
      { ref: "6050", name: "關山", lon: 121.161111, lat: 23.045833 }
    ].freeze

    YILAN_FALLBACK_STATIONS = [
      { ref: "7120", name: "蘇澳", lon: 121.8514536, lat: 24.5951769 }
    ].freeze

    HUALIEN_PORT_FALLBACK_STATIONS = [
      { ref: "6256", name: "花蓮港", lon: 121.63722, lat: 23.99417 }
    ].freeze

    TAICHUNG_PORT_FALLBACK_STATIONS = [
      { ref: "2211", name: "一號碼頭", lon: 120.5533791, lat: 24.2944089 }
    ].freeze

    TAICHUNG_PORT_FALLBACK_STATIONS = [
      { ref: "2218", name: "一號碼頭", lon: 120.5533791, lat: 24.2944089 }
    ].freeze

    PINGTUNG_FALLBACK_STATIONS = [
      { ref: "4400", name: "高雄", lon: 120.3025585, lat: 22.6395321 },
      { ref: "4410", name: "民族", lon: 120.3150956, lat: 22.6387002 },
      { ref: "4420", name: "科工館", lon: 120.3263501, lat: 22.6370734 },
      { ref: "4430", name: "正義", lon: 120.3427383, lat: 22.6341158 },
      { ref: "4440", name: "鳳山", lon: 120.357658, lat: 22.631431 },
      { ref: "4450", name: "後庄", lon: 120.3910467, lat: 22.6404643 },
      { ref: "4460", name: "九曲堂", lon: 120.4212016, lat: 22.6559651 },
      { ref: "4470", name: "六塊厝", lon: 120.4648193, lat: 22.665782 },
      { ref: "5000", name: "屏東", lon: 120.4861261, lat: 22.6688534 },
      { ref: "5010", name: "歸來", lon: 120.5027937, lat: 22.6522748 },
      { ref: "5020", name: "麟洛", lon: 120.5142967, lat: 22.6346885 },
      { ref: "5030", name: "西勢", lon: 120.5265105, lat: 22.6162442 },
      { ref: "5040", name: "竹田", lon: 120.5397507, lat: 22.5865768 },
      { ref: "5050", name: "潮州", lon: 120.5360618, lat: 22.5499793 },
      { ref: "5060", name: "崁頂", lon: 120.5148442, lat: 22.5131585 },
      { ref: "5070", name: "南州", lon: 120.5120035, lat: 22.4918686 },
      { ref: "5080", name: "鎮安", lon: 120.5111516, lat: 22.4579911 }
    ].freeze

    def self.cached_stations
      cached = CACHE_PATH.exist? ? JSON.parse(CACHE_PATH.read) : []
      by_ref = cached.each_with_object({}) { |entry, index| index[entry["ref"]] = entry }

      (
        TAIDONG_SOUTHERN_FALLBACK_STATIONS + PINGTUNG_FALLBACK_STATIONS + YILAN_FALLBACK_STATIONS +
          HUALIEN_PORT_FALLBACK_STATIONS + TAICHUNG_PORT_FALLBACK_STATIONS
      ).each do |entry|
        by_ref[entry[:ref]] ||= {
          "ref" => entry[:ref], "name" => entry[:name], "lon" => entry[:lon], "lat" => entry[:lat]
        }
      end

      by_ref.values.sort_by { |entry| entry["ref"].to_i }.map do |entry|
        { ref: entry["ref"], name: entry["name"], lon: entry["lon"], lat: entry["lat"] }
      end
    end

    def self.excluded_refs_for(line_slug)
      EXCLUDED_REFS_BY_LINE.fetch(line_slug, [])
    end
  end
end
