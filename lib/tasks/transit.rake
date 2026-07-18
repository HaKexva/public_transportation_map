# frozen_string_literal: true

namespace :transit do
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

  desc "Import TRA/HSR/metro schedules from TDX API (requires TDX_CLIENT_ID and TDX_CLIENT_SECRET)"
  task import_schedules: :environment do
    unless Transit::TdxClient.configured?
      abort "Missing TDX credentials. Set TDX_CLIENT_ID and TDX_CLIENT_SECRET in .env or Rails credentials."
    end

    systems = ENV.fetch("SYSTEMS", "tra,hsr,metro").split(",").map(&:strip).reject(&:empty?)
    result = Transit::ScheduleImporter.import!(systems: systems)
    puts "Imported dataset ##{result.dataset.id}: #{result.trips} trips, #{result.headways} headway rules (#{result.skipped} skipped)"
  end

  desc "Sync catalog and load sample + other + sugar railway schedules"
  task prepare_schedules: %i[sync_catalog seed_sample_schedules seed_other_schedules seed_sugar_schedules]
end
