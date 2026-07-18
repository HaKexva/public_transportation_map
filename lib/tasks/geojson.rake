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

  desc "Rebuild Taiwan Sugar Railway (糖鐵) GeoJSON files from OpenStreetMap"
  task sugar_railway: :environment do
    Geojson::MetroSystemImporter.import!(
      system_id: "sugar_railway",
      lines: Geojson::SugarRailwayCatalog::LINES
    )
  end

  desc "Rebuild 文湖線 GeoJSON from OpenStreetMap track geometry"
  task wenhu: :environment do
    line = Geojson::TaipeiMetroCatalog::LINES.find { |entry| entry.slug == "wenhu_line" }
    Geojson::MetroLineBuilder.build!(line)
  end

  desc "Rebuild Taichung Metro line GeoJSON files from OpenStreetMap"
  task taichung_metro: :environment do
    Geojson::MetroSystemImporter.import!(
      system_id: "taichung_metro",
      lines: Geojson::TaichungMetroCatalog::LINES
    )
  end

  desc "Rebuild Kaohsiung Metro line GeoJSON files from OpenStreetMap"
  task kaohsiung_metro: :environment do
    Geojson::MetroSystemImporter.import!(
      system_id: "kaohsiung_metro",
      lines: Geojson::KaohsiungMetroCatalog::LINES
    )
  end

  desc "Rebuild Taiwan High Speed Rail GeoJSON from OpenStreetMap"
  task hsr: :environment do
    Geojson::MetroSystemImporter.import!(
      system_id: "hsr",
      lines: Geojson::HsrCatalog::LINES
    )
  end

  desc "Rebuild Taiwan Railway (TRA) GeoJSON from OpenStreetMap"
  task tra: :environment do
    Geojson::MetroSystemImporter.import!(
      system_id: "tra",
      lines: Geojson::TraCatalog::LINES
    )
  end

  desc "Refresh TRA station refs/coords on existing track GeoJSON (shared numeric codes)"
  task refresh_tra_stations: :environment do
    Geojson::MetroLineBuilder.refresh_all_tra_stations!
  end

  desc "Apply transit transfer combined refs to on-disk station features"
  task refresh_transfer_refs: :environment do
    updated = Geojson::TransitTransferRefresher.refresh!
    if updated.empty?
      puts "No transfer refs updated."
    else
      updated.each { |entry| puts "Updated #{entry}" }
    end
  end

  desc "Rebuild TRA GeoJSON using cached track fallbacks when Overpass is unavailable"
  task tra_offline: :environment do
    Geojson::MetroLineBuilder.offline_tra_build = true
    Geojson::MetroLineBuilder.reset_tra_station_cache!
    Geojson::TraCatalog::LINES.each do |line|
      Geojson::MetroLineBuilder.build!(line)
    rescue StandardError => error
      warn "Skipped #{line.slug}: #{error.message}"
    end
    Geojson::RoutesManifestWriter.write!
  end

  desc "Write metro depot markers JSON from catalog"
  task depots: :environment do
    Geojson::MetroDepotCatalog.write_json!
  end

  desc "Refresh cached yard spur geometry for maintenance depots (NLSC open data first, then OSM)"
  task depot_spurs: :environment do
    Geojson::DepotSpurCatalog.refresh_cache!
    Geojson::MetroDepotCatalog.write_json!
    updated = Geojson::DepotSpurRefresher.refresh_all!
    puts "Updated depot spurs in #{updated.length} route files"
  end

  namespace :nlsc_railways do
    desc "Download NLSC open railway centerlines (TRA / HSR / MRT)"
    task download: :environment do
      Geojson::NlscRailwayCatalog::DATASETS.each_key do |key|
        path = Geojson::NlscRailwayCatalog.ensure_dataset!(key)
        puts "Cached #{key} -> #{path}"
      end
    end

    desc "Build per-depot spur caches from NLSC railway centerlines"
    task depot_spurs: :environment do
      updated = Geojson::NlscRailwayCatalog.refresh_all_depot_caches!
      puts "Wrote #{updated.length} NLSC depot spur caches"
    end
  end

  desc "Rewrite routes.json from on-disk GeoJSON and line catalogs"
  task routes_manifest: :environment do
    Geojson::RoutesManifestWriter.write!
  end
end
