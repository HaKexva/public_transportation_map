# frozen_string_literal: true

module Geojson
  class TaipeiMetroImporter
    def self.import!
      MetroSystemImporter.import!(
        system_id: "taipei_metro",
        lines: TaipeiMetroCatalog::LINES
      )
    end
  end
end
