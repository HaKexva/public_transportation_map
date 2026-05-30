# frozen_string_literal: true

namespace :geojson do
  desc "Rebuild all Taipei Metro line GeoJSON files from OpenStreetMap"
  task taipei_metro: :environment do
    Geojson::TaipeiMetroImporter.import!
  end

  desc "Rebuild New Taipei Metro line GeoJSON files from OpenStreetMap"
  task new_taipei_metro: :environment do
    Geojson::MetroSystemImporter.import!(
      system_id: "new_taipei_metro",
      lines: Geojson::NewTaipeiMetroCatalog::LINES
    )
  end

  desc "Rebuild Taoyuan Metro line GeoJSON files from OpenStreetMap"
  task taoyuan_metro: :environment do
    Geojson::MetroSystemImporter.import!(
      system_id: "taoyuan_metro",
      lines: Geojson::TaoyuanMetroCatalog::LINES
    )
    Geojson::AirportMrtExpressBuilder.build!
  end

  desc "Rebuild Airport MRT express GeoJSON from the main airport line"
  task airport_mrt_express: :environment do
    Geojson::AirportMrtExpressBuilder.build!
  end

  desc "Rebuild other transit line GeoJSON files from OpenStreetMap"
  task other: :environment do
    Geojson::MetroSystemImporter.import!(
      system_id: "other",
      lines: Geojson::OtherTransitCatalog::LINES
    )
  end

  desc "Rebuild 文湖線 GeoJSON from OpenStreetMap track geometry"
  task wenhu: :environment do
    line = Geojson::TaipeiMetroCatalog::LINES.find { |entry| entry.slug == "wenhu_line" }
    Geojson::MetroLineBuilder.build!(line)
  end

  desc "Write metro depot markers JSON from catalog"
  task depots: :environment do
    Geojson::MetroDepotCatalog.write_json!
  end
end
