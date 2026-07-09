# frozen_string_literal: true

module Geojson
  module NewTaipeiMetroCatalog
    DANHAI_COLOR = "#ED6B46"
    # 紅樹林～濱海沙崙：綠山／藍海重疊區（新北捷運班距重疊區 V01–V09）
    DANHAI_SHARED_STATION_REFS = (1..9).map { |index| format("V%02d", index) }.freeze
    DANHAI_LANHAI_ONLY_STATION_REFS = %w[V28 V27 V26].freeze
    # V09 濱海沙崙後依行車方向：海洋大學 → 沙崙 → 漁人碼頭（終點）
    DANHAI_LANHAI_STATION_ORDER = DANHAI_LANHAI_ONLY_STATION_REFS.freeze
    DANHAI_SHARED_ORIGIN_REF = "V01"
    DANHAI_LUSHAN_DESTINATION_REF = "V11"
    DANHAI_LANHAI_DESTINATION_REF = "V26"
    # OSM relations often omit these; keep official stops for map labels and transfers.
    DANHAI_FALLBACK_STATIONS = [
      { ref: "V01", name: "紅樹林", lon: 121.4589125, lat: 25.15544 },
      { ref: "V02", name: "竿蓁林", lon: 121.456225, lat: 25.1621824 },
      { ref: "V11", name: "崁頂", lon: 121.434621, lat: 25.2009501 },
      { ref: "V26", name: "淡水漁人碼頭", lon: 121.4186124, lat: 25.1820049 },
      { ref: "V27", name: "沙崙", lon: 121.41719, lat: 25.18745 },
      { ref: "V28", name: "臺北海洋大學", lon: 121.426285, lat: 25.1911611 }
    ].freeze

    LINES = [
      MetroLine.new_taipei(
        slug: "danhai_lrt",
        name: "淡海輕軌",
        name_en: "Danhai LRT",
        ref: "V",
        color: DANHAI_COLOR,
        relation_ids: [ 9154523, 13611116 ],
        station_ref_prefix: "V"
      ),
      MetroLine.new_taipei(
        slug: "ankeng_lrt",
        name: "安坑輕軌",
        name_en: "Ankeng LRT",
        ref: "K",
        color: "#C3B091",
        relation_ids: [ 15443525 ],
        station_ref_prefix: "K"
      ),
      MetroLine.new_taipei(
        slug: "sanying_line",
        name: "三鶯線",
        name_en: "Sanying Line",
        ref: "LB",
        color: "#6DB7D0",
        relation_ids: [ 5_341_250 ],
        station_ref_prefix: "LB"
      )
    ].freeze
  end
end
