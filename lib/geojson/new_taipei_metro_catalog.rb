# frozen_string_literal: true

module Geojson
  module NewTaipeiMetroCatalog
    DANHAI_COLOR = "#ED6B46"
    # 紅樹林～濱海沙崙：綠山／藍海重疊區（新北捷運班距重疊區 V01–V09）
    DANHAI_SHARED_STATION_REFS = (1..9).map { |index| format("V%02d", index) }.freeze
    DANHAI_LANHAI_ONLY_STATION_REFS = %w[V26 V27 V28].freeze
    # OSM relations often omit these; keep official stops for map labels and transfers.
    DANHAI_FALLBACK_STATIONS = [
      { ref: "V01", name: "紅樹林", lon: 121.4589125, lat: 25.15544 },
      { ref: "V02", name: "竿蓁林", lon: 121.456225, lat: 25.1621824 },
      { ref: "V11", name: "崁頂", lon: 121.434621, lat: 25.2009501 },
      { ref: "V27", name: "沙崙", lon: 121.41719, lat: 25.18745 }
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
      )
    ].freeze
  end
end
