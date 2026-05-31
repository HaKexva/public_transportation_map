# frozen_string_literal: true

module Geojson
  module TaichungMetroCatalog
    # Used when Overpass station queries are slow or incomplete.
    FALLBACK_STATIONS = [
      { ref: "103a", name: "北屯總站", lon: 120.717, lat: 24.187 },
      { ref: "103", name: "舊社", lon: 120.707, lat: 24.179 },
      { ref: "104", name: "松竹", lon: 120.697, lat: 24.180 },
      { ref: "105", name: "四維國小", lon: 120.684, lat: 24.170 },
      { ref: "106", name: "文心崇德", lon: 120.684, lat: 24.172 },
      { ref: "107", name: "文心中清", lon: 120.674, lat: 24.172 },
      { ref: "108", name: "文華高中", lon: 120.665, lat: 24.172 },
      { ref: "109", name: "文心櫻花", lon: 120.655, lat: 24.163 },
      { ref: "110", name: "市政府", lon: 120.648, lat: 24.161 },
      { ref: "111", name: "水安宮", lon: 120.643, lat: 24.152 },
      { ref: "112", name: "文心森林公園", lon: 120.646, lat: 24.145 },
      { ref: "113", name: "南屯", lon: 120.644, lat: 24.137 },
      { ref: "114", name: "豐樂公園", lon: 120.638, lat: 24.129 },
      { ref: "115", name: "大慶", lon: 120.648, lat: 24.119 },
      { ref: "116", name: "九張犁", lon: 120.639, lat: 24.110 },
      { ref: "117", name: "九德", lon: 120.615, lat: 24.099 },
      { ref: "118", name: "烏日", lon: 120.622, lat: 24.090 },
      { ref: "119", name: "高鐵臺中站", lon: 120.616, lat: 24.111 }
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
