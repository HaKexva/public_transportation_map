# frozen_string_literal: true

module Geojson
  module OtherTransitCatalog
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
        relation_ids: [ 17666637, 17666651 ],
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
