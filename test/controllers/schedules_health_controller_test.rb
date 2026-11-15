# frozen_string_literal: true

require "test_helper"

class SchedulesHealthControllerTest < ActionDispatch::IntegrationTest
  test "reports a fresh active dataset" do
    ScheduleDataset.tdx.active.update_all(active: false)
    ScheduleDataset.create!(name: "TDX", source: "tdx", active: true, imported_at: 1.hour.ago)

    get schedules_health_check_url

    assert_response :success
    assert_equal "ok", response.body
  end

  test "keeps an old active dataset" do
    ScheduleDataset.tdx.active.update_all(active: false)
    ScheduleDataset.create!(name: "TDX", source: "tdx", active: true, imported_at: 30.days.ago)

    get schedules_health_check_url

    assert_response :success
  end

  test "fails when no active dataset exists" do
    ScheduleDataset.tdx.active.update_all(active: false)

    get schedules_health_check_url

    assert_response :service_unavailable
  end
end
