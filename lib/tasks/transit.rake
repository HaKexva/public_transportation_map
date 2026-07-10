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

  desc "Sync catalog and load sample schedules"
  task prepare_schedules: %i[sync_catalog seed_sample_schedules]
end
