# frozen_string_literal: true

require "test_helper"

class TransitImportSchedulesJobTest < ActiveJob::TestCase
  test "no-ops when TDX is not configured" do
    client = Object.new
    def client.configured? = false

    other = Transit::OtherTransitScheduleSeeder.method(:seed!)
    sugar = Transit::SugarRailwayScheduleSeeder.method(:seed!)
    Transit::OtherTransitScheduleSeeder.define_singleton_method(:seed!) { true }
    Transit::SugarRailwayScheduleSeeder.define_singleton_method(:seed!) { true }

    assert_no_difference("ScheduleDataset.count") do
      Transit::ImportSchedulesJob.perform_now(client: client)
    end
  ensure
    Transit::OtherTransitScheduleSeeder.define_singleton_method(:seed!, other) if other
    Transit::SugarRailwayScheduleSeeder.define_singleton_method(:seed!, sugar) if sugar
  end
end
