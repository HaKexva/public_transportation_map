# frozen_string_literal: true

module Geojson
  module NewTaipeiMetroCatalog
    LINES = [
      MetroLine.new_taipei(
        slug: "danhai_lrt",
        name: "淡海輕軌",
        name_en: "Danhai LRT",
        ref: "V",
        color: "#ED6B46",
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
