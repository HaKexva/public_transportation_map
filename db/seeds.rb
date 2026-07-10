# frozen_string_literal: true

# Populate transit routes/stations from on-disk GeoJSON, then optional demo schedules.
Transit::CatalogSync.sync!
Transit::SampleScheduleSeeder.seed! if Rails.env.development?
