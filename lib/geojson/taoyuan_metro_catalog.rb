# frozen_string_literal: true

module Geojson
  module TaoyuanMetroCatalog
    LINES = [
      MetroLine.taoyuan(
        slug: "airport_mrt",
        name: "機場捷運",
        name_en: "Taoyuan Airport MRT",
        ref: "A",
        color: "#0073B7",
        relation_ids: [ 6937083 ],
        station_ref_prefix: "A"
      )
    ].freeze
  end
end
