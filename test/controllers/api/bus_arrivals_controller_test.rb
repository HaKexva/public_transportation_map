# frozen_string_literal: true

require "test_helper"

class ApiBusArrivalsControllerTest < ActionDispatch::IntegrationTest
  test "index returns empty arrivals when stop uid missing" do
    get api_bus_arrivals_url, params: { city_id: "Taoyuan" }
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal [], body["arrivals"]
    assert_equal "missing_stop", body["error"]
  end

  test "index returns empty arrivals for unknown city" do
    get api_bus_arrivals_url, params: { city_id: "NotACity", stop_uid: "TAO1" }
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal [], body["arrivals"]
    assert_equal "unknown_city", body["error"]
  end
end
