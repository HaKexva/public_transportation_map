# frozen_string_literal: true

require "test_helper"

class Api::SchedulesControllerTest < ActionDispatch::IntegrationTest
  test "index returns empty routes without ids" do
    get api_schedules_url, params: { date: "2026-08-04" }
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "2026-08-04", body["date"]
    assert_equal [], body["routes"]
  end

  test "index rejects invalid dates" do
    get api_schedules_url, params: { date: "not-a-date", route_ids: [ "bannan" ] }
    assert_response :bad_request
  end
end
