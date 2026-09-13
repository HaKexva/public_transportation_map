# frozen_string_literal: true

module Transit
  class ImportSchedulesJob < ApplicationJob
    queue_as :default

    def perform(systems: %w[tra hsr metro], client: TdxClient.new)
      systems = Array(systems).map(&:to_s)
      OtherTransitScheduleSeeder.seed!
      SugarRailwayScheduleSeeder.seed!

      tdx_needed = (systems & %w[hsr metro]).any?
      return if tdx_needed && !client.configured?

      ScheduleImporter.import!(client: client, systems: systems)
    end
  end
end
