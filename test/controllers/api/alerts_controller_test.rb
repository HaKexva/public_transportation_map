# frozen_string_literal: true

require "test_helper"

class Api::AlertsControllerTest < ActionDispatch::IntegrationTest
  test "index returns the feed alerts" do
    original = Transit::MetroAlertFeed.method(:call)
    Transit::MetroAlertFeed.define_singleton_method(:call) do |**|
      [ { id: "TRTC:42", operator: "台北捷運", title: "列車延誤" } ]
    end

    get api_alerts_url

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal [ "TRTC:42" ], body["alerts"].map { |alert| alert["id"] }
  ensure
    Transit::MetroAlertFeed.define_singleton_method(:call, original)
  end
end
