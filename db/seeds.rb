# frozen_string_literal: true

# Populate transit routes/stations from on-disk GeoJSON, then published schedules.
# TDX 台鐵／高鐵／捷運時刻表 is imported separately (rake or daily job) so boot
# and CI are not blocked on a long API pull.
Transit::CatalogSync.sync!

unless Rails.env.test?
  Transit::OtherTransitScheduleSeeder.seed!
  Transit::SugarRailwayScheduleSeeder.seed!

  if Rails.env.production? && Transit::TdxClient.configured? && !ScheduleDataset.tdx.active.exists?
    Transit::ImportSchedulesJob.perform_later
  end

  # Fallback until a TDX snapshot exists (SampleScheduleSeeder no-ops once TDX is active).
  Transit::SampleScheduleSeeder.seed!
end
