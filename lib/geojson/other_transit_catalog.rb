# frozen_string_literal: true

module Geojson
  module OtherTransitCatalog
    # Passenger + angle stops along the Maokong Gondola (OSM way 71266575).
    MAOKONG_FALLBACK_STATIONS = [
      { ref: "G1", name: "動物園", lon: 121.5762884, lat: 24.9959573 },
      { ref: "G2", name: "轉角一", lon: 121.5829967, lat: 24.9919382, angle_station: true },
      { ref: "G3", name: "動物園南", lon: 121.5874945, lat: 24.9901573 },
      { ref: "G4", name: "轉角二", lon: 121.5921614, lat: 24.9882953, angle_station: true },
      { ref: "G5", name: "指南宮", lon: 121.5896828, lat: 24.9789312 },
      { ref: "G6", name: "貓空", lon: 121.5881712, lat: 24.9691386 }
    ].freeze

    LINES = [
      MetroLine.other(
        slug: "maokong_gondola",
        name: "貓空纜車",
        name_en: "Maokong Gondola",
        ref: "MG",
        color: "#00AFE2",
        way_ids: [ 71266575 ],
        station_ref_prefix: "MG"
      ),
      MetroLine.other(
        slug: "taoyuan_airport_skytrain",
        name: "桃園機場南北側電車",
        name_en: "Taoyuan Airport Skytrain",
        ref: "ST",
        color: "#4F46E5",
        relation_ids: [],
        way_ids: [ 256726319, 256726320 ],
        station_ref_prefix: "ST"
      ),
      MetroLine.other(
        slug: "sun_moon_ropeway",
        name: "九族文化村－日月潭纜車",
        name_en: "Sun Moon Lake Ropeway",
        ref: "SM",
        color: "#059669",
        way_ids: [ 65630200 ],
        station_ref_prefix: "SM"
      )
    ].freeze
  end
end
