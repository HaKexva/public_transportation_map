# frozen_string_literal: true

module Geojson
  module HsrCatalog
    # THSR corporate identity orange (not purple).
    BRAND_COLOR = "#F4811A".freeze

    # North → south station order (Taiwan HSR).
    STATION_ORDER = [
      "南港",
      "台北",
      "板橋",
      "桃園",
      "新竹",
      "苗栗",
      "台中",
      "彰化",
      "雲林",
      "嘉義",
      "台南",
      "左營"
    ].freeze

    STATION_REFS_BY_NAME = STATION_ORDER.each_with_index.to_h do |name, index|
      [ name, format("%02d", index + 1) ]
    end.freeze

    # Used when Overpass is slow or station tags are incomplete.
    FALLBACK_STATIONS = [
      { ref: "01", name: "南港", lon: 121.6069, lat: 25.0522 },
      { ref: "02", name: "台北", lon: 121.5170, lat: 25.0483 },
      { ref: "03", name: "板橋", lon: 121.463675, lat: 25.014281 },
      { ref: "04", name: "桃園", lon: 121.2148, lat: 25.0131 },
      { ref: "05", name: "新竹", lon: 120.9980, lat: 24.8080 },
      { ref: "06", name: "苗栗", lon: 120.7410, lat: 24.6050 },
      { ref: "07", name: "台中", lon: 120.6160, lat: 24.1110 },
      { ref: "08", name: "彰化", lon: 120.5740, lat: 23.8740 },
      { ref: "09", name: "雲林", lon: 120.4160, lat: 23.7360 },
      { ref: "10", name: "嘉義", lon: 120.3220, lat: 23.4590 },
      { ref: "11", name: "台南", lon: 120.2860, lat: 22.9240 },
      { ref: "12", name: "左營", lon: 120.3070, lat: 22.6870 }
    ].freeze

    LINES = [
      MetroLine.hsr(
        slug: "taiwan_hsr",
        name: "台灣高鐵",
        name_en: "Taiwan High Speed Rail",
        ref: "HSR",
        color: BRAND_COLOR,
        relation_ids: [ 4_500_369, 4_500_371 ],
        station_ref_prefix: "HSR"
      )
    ].freeze
  end
end
