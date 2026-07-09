# frozen_string_literal: true

module Geojson
  module KaohsiungMetroCatalog
    # Same-system in-station transfers (shown as two-color markers).
    IN_STATION_TRANSFERS_BY_NAME = {
      "美麗島" => { combined_ref: "R10;O5", lon: 120.302098, lat: 22.631357 }
    }.freeze

    CIRCULAR_LRT_IN_STATION_TRANSFERS_BY_NAME = {}.freeze

    # Cross-route transfers with physically separate platforms (shown as two stations).
    CROSS_ROUTE_TRANSFERS_BY_NAME = {
      "哈瑪星" => {
        combined_ref: "C14;O1",
        lines: %w[circular_lrt orange_line],
        coordinates_by_ref: {
          "C14" => { lon: 120.2758505, lat: 22.6216067 },
          "O1" => { lon: 120.2734156, lat: 22.6221059 }
        }
      }
    }.freeze

    # RK1 opened 2024-06; may be missing from OSM relation station lists.
    RED_LINE_FALLBACK_STATIONS = [
      { ref: "RK1", name: "岡山車站", lon: 120.2990202, lat: 22.7925917 }
    ].freeze

    LINES = [
      MetroLine.kaohsiung(
        slug: "red_line",
        name: "紅線",
        name_en: "Red Line",
        ref: "R",
        color: "#E3002C",
        relation_ids: [ 6_825_396, 4_174_828 ],
        station_ref_prefix: "R"
      ),
      MetroLine.kaohsiung(
        slug: "orange_line",
        name: "橘線",
        name_en: "Orange Line",
        ref: "O",
        color: "#FAA73F",
        relation_ids: [ 4_174_827, 6_825_570 ],
        station_ref_prefix: "O"
      ),
      MetroLine.kaohsiung(
        slug: "circular_lrt",
        name: "環狀輕軌",
        name_en: "Circular Light Rail",
        ref: "C",
        color: "#ADC956",
        relation_ids: [ 6_826_886 ],
        station_ref_prefix: "C",
        osm_networks: [ "高雄捷運", "高雄大眾捷運系統", "環狀輕軌" ]
      )
    ].freeze
  end
end
