# frozen_string_literal: true

require "test_helper"

class TransitImportSchedulesJobTest < ActiveJob::TestCase
  test "no-ops when TDX is not configured" do
    client = Object.new
    def client.configured? = false

    assert_no_difference("ScheduleDataset.count") do
      Transit::ImportSchedulesJob.perform_now(client: client)
    end
  end
end
