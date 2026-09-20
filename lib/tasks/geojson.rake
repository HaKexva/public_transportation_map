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

  desc "Rebuild Ferry (渡輪) GeoJSON files from OpenStreetMap"
  task ferry: :environment do
    Geojson::MetroSystemImporter.import!(
      system_id: "ferry",
      lines: Geojson::FerryCatalog::LINES
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

  desc "Rewrite bus stop→routes indexes and bus_depots.json from on-disk GeoJSON"
  task bus_stop_index: :environment do
    result = Geojson::BusStopIndexWriter.write!
    puts "Indexed #{result.stations} stations / #{result.clusters} clusters across #{result.cities.length} city folders"
    Geojson::BusDepotWriter.write!
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

    desc "Rebuild TRA fallback track JSON from NLSC centerlines"
    task tra_fallbacks: :environment do
      updated = Geojson::NlscTraCorridorBuilder.rebuild_all!
      puts "Rebuilt #{updated.length} TRA NLSC fallback tracks"
    end
  end

  desc "Import city bus GeoJSON from TDX (CITY=Keelung|InterCity; omit SERIES for all routes)"
  task bus: :environment do
    city = ENV.fetch("CITY", "Keelung")
    series = ENV["SERIES"].presence
    result = Geojson::BusImporter.import!(city_id: city, series: series, prune_stale: series.blank?)
    suffix = series.present? ? " (#{series}xx)" : ""
    puts "Imported #{result.routes.length} bus routes for #{city}#{suffix}"
    puts "Skipped (no shape): #{result.skipped.join(', ')}" if result.skipped.any?
  end

  desc "Import specific bus RouteUIDs via MOTC PTX (CITY=NewTaipei ROUTE_UIDS=NWT18288,TXG2513)"
  task bus_route_uids: :environment do
    city = ENV.fetch("CITY")
    route_uids = ENV.fetch("ROUTE_UIDS").split(",").map(&:strip).reject(&:blank?)
    result = Geojson::BusImporter.import_route_uids!(city_id: city, route_uids: route_uids)
    puts "Imported #{result.routes.length} bus routes for #{city}: #{result.routes.join(', ')}"
    puts "Skipped: #{result.skipped.join(', ')}" if result.skipped.any?
  end

  desc "Import all bus GeoJSON from TDX (ONLY=Taipei,NewTaipei SKIP=Keelung; INCLUDE_INTERCITY=1 for highway coaches)"
  task bus_all: :environment do
    only = ENV["ONLY"].to_s.split(",").map(&:strip).reject(&:blank?)
    skip = ENV["SKIP"].to_s.split(",").map(&:strip).reject(&:blank?)
    include_intercity = ENV["INCLUDE_INTERCITY"].to_s.match?(/\A(1|true|yes)\z/i)
    cities = Geojson::BusCatalog.cities
    cities = cities.reject { |city| city.kind == :intercity } unless include_intercity || only.include?("InterCity")
    cities = cities.select { |city| only.include?(city.id) } if only.any?
    cities = cities.reject { |city| skip.include?(city.id) } if skip.any?

    if cities.empty?
      abort "No cities selected (check ONLY=/SKIP=/INCLUDE_INTERCITY= against BusCatalog)"
    end

    totals = { routes: 0, skipped: 0 }
    cities.each do |city|
      puts "=== #{city.id} ==="
      result = Geojson::BusImporter.import!(
        city_id: city.id,
        prune_stale: true,
        rewrite_manifest: false
      )
      totals[:routes] += result.routes.length
      totals[:skipped] += result.skipped.length
      puts "Imported #{result.routes.length} bus routes for #{city.id}"
      puts "Skipped (no shape): #{result.skipped.join(', ')}" if result.skipped.any?
    end

    Geojson::RoutesManifestWriter.write!
    Geojson::BusStopIndexWriter.write!
    Geojson::BusDepotWriter.write!
    puts "Done. Imported #{totals[:routes]} routes across #{cities.map(&:id).join(', ')} (skipped #{totals[:skipped]})"
  end

  desc "Audit bus coverage: TDX Route/Shape vs local GeoJSON (CITY=MiaoliCounty or omit for all; OUT=tmp/bus_coverage)"
  task bus_coverage: :environment do
    city_ids = ENV["CITY"].to_s.split(",").map(&:strip).reject(&:blank?)
    output_dir = ENV["OUT"].presence
    local_only = ENV["LOCAL_ONLY"].to_s.match?(/\A(1|true|yes)\z/i)

    report = if local_only
      Geojson::BusCoverageAuditor.export_local_gaps!(output_dir: output_dir)
    else
      Geojson::BusCoverageAuditor.audit!(city_ids: city_ids.presence, output_dir: output_dir)
    end

    puts "Missing official maps: #{report.missing_official_maps.length}"
    puts "Thin geometry: #{report.thin_geometry.length}"
    if report.cities.any?
      no_shape = report.cities.sum { |city| city.no_shape.length }
      not_imported = report.cities.sum { |city| city.not_imported.length }
      puts "TDX no-shape: #{no_shape}; has-shape not imported: #{not_imported}"
    end
  end

  desc "Export local bus gaps only (missing official_map_url + thin geometry) to OUT=docs/bus_data_gaps"
  task bus_gaps_export: :environment do
    output_dir = ENV["OUT"].presence || Rails.root.join("docs/bus_data_gaps").to_s
    report = Geojson::BusCoverageAuditor.export_local_gaps!(output_dir: output_dir)
    puts "Exported #{report.missing_official_maps.length} missing official maps and #{report.thin_geometry.length} thin geometry rows to #{output_dir}"
  end

  desc "Import manual bus drops from inbox/bus_manual and annotated missing_official_maps.md URLs"
  task bus_manual_import: :environment do
    result = Geojson::BusManualImporter.import!
    puts "Updated official maps / geometry for #{result.updated_slugs.uniq.length} routes"
    puts "Imported geometry: #{result.imported_geometry.join(', ')}" if result.imported_geometry.any?
    puts "Skipped: #{result.skipped.join(', ')}" if result.skipped.any?
  end

  desc "Move bus GeoJSON into per-city folders under public/geojson/bus/"
  task bus_reorganize: :environment do
    result = Geojson::BusReorganizer.reorganize!
    puts "Moved #{result.moved.length} routes into city folders"
    puts "Already placed: #{result.already_placed.length}"
    puts "Skipped: #{result.skipped.length}" if result.skipped.any?
  end

  desc "Sharpen bus route corners on disk (CITY=Keelung; omit for all cities)"
  task bus_sharpen: :environment do
    city_ids = ENV["CITY"].to_s.split(",").map(&:strip).reject(&:blank?)
    glob = if city_ids.any?
      city_ids.flat_map { |city_id|
        subdir = Geojson::BusLayout.subdir_for(city_id)
        next [] if subdir.blank?

        Dir.glob(Rails.root.join("public/geojson/bus", subdir, "**/*.geojson"))
      }
    else
      Dir.glob(Rails.root.join("public/geojson/bus/**/*.geojson"))
    end

    updated = 0
    glob.uniq.sort.each do |path|
      data = JSON.parse(File.read(path))
      changed = false
      Array(data["features"]).each do |feature|
        next unless feature.dig("geometry", "type") == "LineString"
        next if feature.dig("properties", "feature_type") == "station"

        original = feature.dig("geometry", "coordinates")
        next if original.blank?

        sharpened = Geojson::BusShapeSharpener.sharpen(original)
        next if sharpened == original

        feature["geometry"]["coordinates"] = sharpened
        changed = true
      end
      next unless changed

      File.write(path, "#{JSON.pretty_generate(data)}\n")
      updated += 1
      puts "Sharpened #{Pathname.new(path).relative_path_from(Rails.root)}"
    end
    puts "Updated #{updated} bus GeoJSON files"
  end

  desc "Sync official_map_url from TDX and operator portals (CITY=Taichung,Taoyuan; SKIP_TDX=1 to only resolve stored portal pages)"
  task bus_official_maps: :environment do
    city_ids = ENV["CITY"].to_s.split(",").map(&:strip).reject(&:blank?)
    sync_tdx = ENV["SKIP_TDX"].to_s != "1"
    result = Geojson::BusOfficialMapFetcher.sync!(city_ids: city_ids.presence, sync_tdx:)
    puts "Updated #{result.updated.length} routes"
    puts "Still missing: #{result.still_missing.length}"
    puts "Skipped: #{result.skipped.length}" if result.skipped.any?
  end

  desc "Cross-check sparse counties against Wikipedia route lists (OUT=docs/bus_data_gaps)"
  task bus_wikipedia_audit: :environment do
    output_dir = ENV["OUT"].presence
    Geojson::BusWikipediaAuditor.audit!(output_dir: output_dir)
  end

  desc "Rewrite routes.json from on-disk GeoJSON and line catalogs"
  task routes_manifest: :environment do
    Geojson::RoutesManifestWriter.write!
    Geojson::BusStopIndexWriter.write!
    Geojson::BusDepotWriter.write!
  end

  desc "Recolor bus GeoJSON: known operators / F-prefix 新巴士 use brand colors; others share a palette by operator"
  task bus_recolor: :environment do
    palette = Geojson::BusImporter::PALETTE
    paths = Dir.glob(Rails.root.join("public/geojson/bus/**/*.geojson")).reject { |path|
      File.basename(path).start_with?("_")
    }

    # Stable palette for operators without a fixed brand color (and not F-prefix 新巴士).
    other_operators = paths.filter_map { |path|
      props = JSON.parse(File.read(path))["properties"] || {}
      next if Geojson::BusOperatorColors.for_route(
        ref: props["ref"],
        name: props["operator"],
        id: props["operator_id"]
      )

      props["operator"].presence
    }.uniq.sort
    fallback_for = other_operators.each_with_index.to_h { |name, index|
      [ name, palette[index % palette.length] ]
    }

    updated = 0
    branded = 0
    paths.each do |path|
      data = JSON.parse(File.read(path))
      properties = data["properties"] || {}
      brand = Geojson::BusOperatorColors.for_route(
        ref: properties["ref"],
        name: properties["operator"],
        id: properties["operator_id"]
      )
      color =
        brand ||
        fallback_for[properties["operator"]] ||
        palette[(properties["operator_id"].presence || properties["id"]).to_s.hash.abs % palette.length]

      next if properties["color"] == color &&
        Array(data["features"]).all? { |feature|
          feature.dig("properties", "color").blank? || feature.dig("properties", "color") == color
        }

      properties["color"] = color
      data["properties"] = properties
      Array(data["features"]).each do |feature|
        next unless feature["properties"].is_a?(Hash)

        feature["properties"]["color"] = color
      end
      File.write(path, "#{JSON.pretty_generate(data)}\n")
      updated += 1
      branded += 1 if brand
    end

    Geojson::RoutesManifestWriter.write!
    puts "Recolored #{updated} bus GeoJSON files (#{branded} brand-mapped, #{other_operators.size} other operators)"
  end

  desc "Merge fragmented bus MULTILINESTRINGs and close circular loop endpoints"
  task bus_close_loops: :environment do
    updated = 0
    Dir.glob(Rails.root.join("public/geojson/bus/**/*.geojson")).each do |path|
      next if File.basename(path).start_with?("_")

      data = JSON.parse(File.read(path))
      next unless Geojson::BusLoopCloser.process_collection!(data)

      File.write(path, "#{JSON.pretty_generate(data)}\n")
      updated += 1
    rescue JSON::ParserError
      next
    end

    Geojson::RoutesManifestWriter.write! if updated.positive?
    puts "Closed/merged loop geometry in #{updated} bus GeoJSON files"
  end

  desc "Estimate TRA level-crossing points from corridor midpoints (not third-party dumps)"
  task level_crossings: :environment do
    count = Geojson::LevelCrossingCatalog.refresh!
    puts "Wrote #{count} estimated level crossings"
  end
end
