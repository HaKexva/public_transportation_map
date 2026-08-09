# frozen_string_literal: true

require "test_helper"

class Api::AlertsControllerTest < ActionDispatch::IntegrationTest
  test "index returns an alerts array" do
    get api_alerts_url
    assert_response :success
    body = JSON.parse(response.body)
    assert_kind_of Array, body["alerts"]
  end
end
