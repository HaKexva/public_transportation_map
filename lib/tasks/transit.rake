# frozen_string_literal: true

namespace :transit do
  desc "Load the old tmp/tdx_bus snapshot files into bus_route_timetables"
  task import_bus_snapshot_files: :environment do
    puts "Imported #{Transit::BusTdxSnapshot.import_files!} bus route timetables"
  end

  desc "Refresh the registered bus fleet (大臺北 open data + TDX Vehicle)"
  task refresh_bus_vehicles: :environment do
    result = Transit::BusFleet.refresh_vehicles!
    puts "Stored #{result[:vehicles]} buses (#{result[:failed].join(', ').presence || 'no failures'})"
  end

  desc "Record which buses are running which routes now (TDX=1 to include TDX cities)"
  task collect_bus_sightings: :environment do
    result = Transit::BusFleet.collect_sightings!(tdx: ENV["TDX"].present?)
    puts "Recorded #{result[:sightings]} route/bus sightings (#{result[:failed].join(', ').presence || 'no failures'})"
  end

  desc "List bus plate series per operator with their mapped model (writes tmp/bus_fleet_series.csv)"
  task bus_fleet_series: :environment do
    require "csv"
    operators = Array(RouteCatalog.manifest["bus"]).each_with_object({}) { |route, names| names[[ route["city_id"], route["operator_id"].to_s ]] ||= route["operator"] }
    operator_name = lambda do |city_id, operator_id|
      operators[[ city_id, operator_id ]] ||
        (Geojson::BusCatalog.greater_taipei_city?(city_id) && Geojson::BusCatalog::GREATER_TAIPEI_CITY_IDS.filter_map { |id| operators[[ id, operator_id ]] }.first)
    end
    seen = BusRouteVehicleSighting.distinct.pluck(:plate).to_set
    groups = BusVehicle.all.group_by { |vehicle| [ vehicle.city_id.to_s, vehicle.operator_id.to_s, Transit::BusVehicleModels.series(vehicle.plate) ] }
    path = Rails.root.join("tmp/bus_fleet_series.csv")
    rows = groups.filter_map do |(city_id, operator_id, series), vehicles|
      next unless series

      sample = vehicles.first
      [ city_id, operator_id, operator_name.call(city_id, operator_id), series, vehicles.size, vehicles.count { |vehicle| seen.include?(vehicle.plate) },
        Transit::BusFleet::VEHICLE_CLASSES[sample.vehicle_class], vehicles.count(&:electric), vehicles.count(&:low_floor),
        vehicles.first(3).map(&:plate).join(" "), Transit::BusVehicleModels.lookup(sample.plate, operator_id, city_id) ]
    end.sort_by { |row| [ row[0], row[1], -row[4] ] }
    CSV.open(path, "w") do |csv|
      csv << %w[city_id operator_id operator series vehicles seen_on_routes class electric low_floor examples model]
      rows.each { |row| csv << row }
    end
    puts "Wrote #{rows.size} series to #{path} (#{rows.count { |row| row.last.nil? }} without a model)"
  end

  desc "Refresh station exits / facilities from TDX into station_infos"
  task refresh_station_info: :environment do
    result = Transit::StationInfoImporter.import!
    puts "Stored #{result[:stations]} stations (#{result[:failed].join(', ').presence || 'no failures'})"
  end

  desc "Sync transit routes and station order from routes.json and GeoJSON"
  task sync_catalog: :environment do
    result = Transit::CatalogSync.sync!
    puts "Synced #{result.routes} routes and #{result.stations} station rows"
  end

  desc "Load sample headway and trip rows for development"
  task seed_sample_schedules: :environment do
    Transit::SampleScheduleSeeder.seed!
    puts "Sample schedule data ready (板南線 weekday demo)"
  end

  desc "Load Alishan Forest Railway timetable (mainline + branch notes)"
  task seed_alishan_schedules: :environment do
    dataset = Transit::AlishanScheduleSeeder.seed!
    puts "Alishan schedule ready: dataset ##{dataset.id} (#{dataset.schedule_trips.count} trips, #{dataset.headway_rules.count} headway rules)"
  end

  desc "Load published timetables for other-system routes (纜車／林鐵／蹦蹦車等)"
  task seed_other_schedules: :environment do
    result = Transit::OtherTransitScheduleSeeder.seed!
    puts "Other schedules ready: dataset ##{result.dataset.id}"
    puts "  routes=#{result.routes} trips=#{result.trips} headways=#{result.headways}"
    puts "  skipped: #{result.skipped.join(', ')}" if result.skipped.any?

    TransitRoute.for_system("other").order(:route_id).each do |route|
      trips = route.schedule_trips.count
      headways = route.headway_rules.count
      next if trips.zero? && headways.zero?

      puts "  - #{route.route_id}: #{trips} trips, #{headways} headways"
    end
  end

  desc "Load published timetables for Taiwan Sugar Railway (糖鐵) routes"
  task seed_sugar_schedules: :environment do
    result = Transit::SugarRailwayScheduleSeeder.seed!
    puts "Sugar railway schedules ready: dataset ##{result.dataset.id}"
    puts "  routes=#{result.routes} trips=#{result.trips} headways=#{result.headways}"
    puts "  skipped: #{result.skipped.join(', ')}" if result.skipped.any?

    TransitRoute.for_system("sugar_railway").order(:route_id).each do |route|
      trips = route.schedule_trips.count
      headways = route.headway_rules.count
      next if trips.zero? && headways.zero?

      puts "  - #{route.route_id}: #{trips} trips, #{headways} headways"
    end
  end

  desc "Import TRA ODS + TDX HSR/metro schedules (HSR/metro need TDX_CLIENT_ID and TDX_CLIENT_SECRET)"
  task import_schedules: :environment do
    $stdout.sync = true
    systems = ENV.fetch("SYSTEMS", "tra,hsr,metro").split(",").map(&:strip).reject(&:empty?)
    tdx_needed = (systems & %w[hsr metro]).any?
    if tdx_needed && !Transit::TdxClient.configured?
      abort "Missing TDX credentials. Set TDX_CLIENT_ID and TDX_CLIENT_SECRET in .env or Rails credentials."
    end

    dataset = ENV["DATASET_ID"].presence && ScheduleDataset.find(ENV["DATASET_ID"])
    inactive = ScheduleDataset.where(source: "tdx", active: false)
    inactive = inactive.where.not(id: dataset.id) if dataset
    removed = ScheduleDataset.discard_ids!(inactive.pluck(:id))
    puts "Discarded #{removed} inactive TDX datasets" if removed.positive?

    unless dataset
      other = Transit::OtherTransitScheduleSeeder.seed!
      sugar = Transit::SugarRailwayScheduleSeeder.seed!
      puts "Other schedules: dataset ##{other.dataset.id} (#{other.trips} trips, #{other.headways} headways)"
      puts "Sugar railway: dataset ##{sugar.dataset.id} (#{sugar.trips} trips, #{sugar.headways} headways)"
    end

    systems = ENV.fetch("SYSTEMS", "tra,hsr,metro").split(",").map(&:strip).reject(&:empty?)
    result = Transit::ScheduleImporter.import!(systems: systems, dataset: dataset)
    puts "Imported TDX dataset ##{result.dataset.id}: #{result.trips} trips, #{result.headways} headway rules (#{result.skipped} skipped)"
  end

  desc "Sync catalog and load sample + other + sugar railway schedules"
  task prepare_schedules: %i[sync_catalog seed_sample_schedules seed_other_schedules seed_sugar_schedules]
end
