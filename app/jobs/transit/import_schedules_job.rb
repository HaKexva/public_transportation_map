# frozen_string_literal: true

module Transit
  class ImportSchedulesJob < ApplicationJob
    queue_as :default

    # force: false keeps the active timetable and only fills 連假 or 颱風假
    # dates that are not stored yet. force: true replaces the whole import.
    def perform(systems: %w[tra hsr metro], client: TdxClient.new(ignore_breaker: true), force: false)
      if force
        perform_full_import(systems:, client:)
      else
        perform_holiday_overlay(client:)
      end
    rescue StandardError => error
      Rails.logger.error("[ImportSchedulesJob] failed: #{error.class}: #{error.message}")
      raise
    end

    private

    def perform_full_import(systems:, client:)
      systems = Array(systems).map(&:to_s)
      OtherTransitScheduleSeeder.seed!
      SugarRailwayScheduleSeeder.seed!

      tdx_needed = (systems & %w[hsr metro]).any?
      return if tdx_needed && !client.configured?

      discard_inactive_datasets
      ScheduleImporter.import!(client: client, systems: systems)
    end

    def perform_holiday_overlay(client:)
      discard_inactive_datasets
      dataset = ScheduleDataset.tdx.active.order(imported_at: :desc, id: :desc).first
      unless dataset
        Rails.logger.info("[ImportSchedulesJob] no active timetable; run transit:import_schedules to load one")
        return
      end

      holiday_dates = TaiwanHolidayCalendar.new.long_weekend_dates(from: Time.zone.today, to: Time.zone.today + 45)
      typhoon_dates = TyphoonClosures.dates
      holiday_missing = missing_dates(dataset, holiday_dates)
      typhoon_missing = missing_dates(dataset, typhoon_dates - holiday_missing)
      if holiday_missing.empty? && typhoon_missing.empty?
        Rails.logger.info("[ImportSchedulesJob] no new holiday or typhoon dates")
        return
      end

      unless client.configured?
        Rails.logger.error("[ImportSchedulesJob] TDX credentials missing; keeping the current timetable")
        return
      end

      import_overlay(dataset, holiday_missing, "連假", client)
      import_overlay(dataset, typhoon_missing, "颱風假", client)
    end

    def missing_dates(dataset, dates)
      dates.reject do |date|
        dataset.service_calendars.exists?(code: "date_#{date.iso8601}", description: ScheduleImporter::OVERLAY_DESCRIPTIONS)
      end
    end

    def import_overlay(dataset, dates, description, client)
      return if dates.empty?

      ScheduleImporter.import_dates!(dataset:, dates:, description:, client:, systems: %w[tra hsr])
    end

    def discard_inactive_datasets
      removed = ScheduleDataset.discard_inactive!(source: "tdx")
      Rails.logger.info("[ImportSchedulesJob] discarded #{removed} inactive tdx datasets") if removed.positive?
    end
  end
end
