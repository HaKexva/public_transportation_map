# frozen_string_literal: true

require "test_helper"

class Transit::MetroAlertFeedTest < ActiveSupport::TestCase
  class FakeClient
    attr_reader :paths

    def initialize(responses, configured: true)
      @responses = responses
      @configured = configured
      @paths = []
    end

    def configured?
      @configured
    end

    def get_json(path, query: {})
      @paths << path
      response = @responses.fetch(path.split("/").last, { "Alerts" => [] })
      raise response if response.is_a?(Exception)

      response
    end
  end

  def normal(id)
    { "AlertID" => id, "Title" => "正常營運", "Description" => "正常營運", "Status" => 1, "Scope" => { "Lines" => [] } }
  end

  test "returns only disruptions with operator context" do
    client = FakeClient.new({
      "TRTC" => { "Alerts" => [
        normal("0"),
        {
          "AlertID" => "42",
          "Title" => "淡水信義線部分區間暫停營運",
          "Description" => "因設備故障，北投至淡水間暫停營運。",
          "Status" => 2,
          "Scope" => { "Lines" => [ { "LineID" => "R" } ] },
          "PublishTime" => "2026-09-27T14:00:05+08:00"
        }
      ] },
      "KRTC" => { "Alerts" => [ normal("mrt_000") ] }
    })

    alerts = Transit::MetroAlertFeed.call(client: client, cache: ActiveSupport::Cache::NullStore.new)

    assert_equal 1, alerts.length
    alert = alerts.first
    assert_equal "TRTC:42", alert[:id]
    assert_equal "taipei_metro", alert[:system_id]
    assert_equal "台北捷運", alert[:operator]
    assert_equal "淡水信義線部分區間暫停營運", alert[:title]
    assert_equal "因設備故障，北投至淡水間暫停營運。", alert[:message]
    assert_equal [ "R" ], alert[:lines]
    assert_equal "https://www.metro.taipei/", alert[:url]
    assert_equal Transit::MetroAlertFeed::OPERATORS.length, client.paths.length
  end

  test "one failing operator does not hide the others" do
    client = FakeClient.new({
      "TRTC" => Transit::TdxClient::RequestError.new("TDX 503"),
      "TYMC" => { "Alerts" => [ { "AlertID" => "9", "Title" => "列車延誤", "Description" => "列車延誤", "Status" => 2 } ] }
    })

    alerts = Transit::MetroAlertFeed.call(client: client, cache: ActiveSupport::Cache::NullStore.new)

    assert_equal [ "TYMC:9" ], alerts.map { |alert| alert[:id] }
    assert_nil alerts.first[:message]
  end

  test "is empty without TDX credentials" do
    client = FakeClient.new({}, configured: false)

    assert_empty Transit::MetroAlertFeed.call(client: client, cache: ActiveSupport::Cache::NullStore.new)
    assert_empty client.paths
  end
end
