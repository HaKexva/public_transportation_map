# frozen_string_literal: true

module Geojson
  module TaichungMetroCatalog
    # Station coordinates from OpenStreetMap nodes (railway=station, ref=103a–119)
    # queried 2025-05; 103a and 116–119 cross-checked with Wikipedia station articles.
    FALLBACK_STATIONS = [
      { ref: "103a", name: "北屯總站", lon: 120.709440, lat: 24.185280 },
      { ref: "103", name: "舊社", lon: 120.707311, lat: 24.182334 },
      { ref: "104", name: "松竹", lon: 120.701397, lat: 24.180730 },
      { ref: "105", name: "四維國小", lon: 120.693254, lat: 24.171259 },
      { ref: "106", name: "文心崇德", lon: 120.684989, lat: 24.172189 },
      { ref: "107", name: "文心中清", lon: 120.670588, lat: 24.173699 },
      { ref: "108", name: "文華高中", lon: 120.660652, lat: 24.171505 },
      { ref: "109", name: "文心櫻花", lon: 120.653890, lat: 24.167780 },
      { ref: "110", name: "市政府", lon: 120.649235, lat: 24.162098 },
      { ref: "111", name: "水安宮", lon: 120.646780, lat: 24.153239 },
      { ref: "112", name: "文心森林公園", lon: 120.646717, lat: 24.145432 },
      { ref: "113", name: "南屯", lon: 120.646692, lat: 24.140549 },
      { ref: "114", name: "豐樂公園", lon: 120.646442, lat: 24.132360 },
      { ref: "115", name: "大慶", lon: 120.647505, lat: 24.119056 },
      { ref: "116", name: "九張犁", lon: 120.641389, lat: 24.114444 },
      { ref: "117", name: "九德", lon: 120.634444, lat: 24.111111 },
      { ref: "118", name: "烏日", lon: 120.625032, lat: 24.108828 },
      { ref: "119", name: "高鐵臺中站", lon: 120.614252, lat: 24.110103 }
    ].freeze

    LINES = [
      MetroLine.taichung(
        slug: "green_line",
        name: "綠線",
        name_en: "Green Line",
        ref: "1",
        color: "#8FC31F",
        relation_ids: [ 11_330_355, 11_330_356 ],
        station_ref_prefix: ""
      )
    ].freeze
  end
end
