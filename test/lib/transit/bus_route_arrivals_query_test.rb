# frozen_string_literal: true

require "test_helper"

class TransitBusRouteArrivalsQueryTest < ActiveSupport::TestCase
  class FakeClient
    def initialize(rows)
      @rows = rows
    end

    def configured?
      true
    end

    def get_json(_path, query: {})
      @rows
    end
  end

  ROUTE = { "id" => "taipei_test_1", "ref" => "0東", "city_id" => "Taipei" }.freeze

  def build(rows)
    Transit::BusRouteArrivalsQuery.new(route_id: ROUTE["id"], client: FakeClient.new(rows), route: ROUTE.dup)
  end

  test "keeps the soonest ETA per stop and direction and maps statuses" do
    stops = build([
      { "StopUID" => "TPE1", "StopName" => { "Zh_tw" => "甲" }, "Direction" => 0, "EstimateTime" => 600, "StopStatus" => 0 },
      { "StopUID" => "TPE1", "StopName" => { "Zh_tw" => "甲" }, "Direction" => 0, "EstimateTime" => 120, "StopStatus" => 0 },
      { "StopUID" => "TPE1", "StopName" => { "Zh_tw" => "甲" }, "Direction" => 1, "StopStatus" => 1,
        "NextBusTime" => "2026-10-01T21:05:00+08:00" },
      { "StopUID" => "TPE2", "StopName" => { "Zh_tw" => "乙" }, "Direction" => 0, "StopStatus" => 3 }
    ]).call[:stops]

    by_key = stops.index_by { |stop| [ stop[:stop_uid], stop[:direction] ] }
    assert_equal 3, stops.size
    assert_equal 120, by_key[[ "TPE1", 0 ]][:estimate_seconds]
    assert_equal "not_departed", by_key[[ "TPE1", 1 ]][:status]
    assert_equal "21:05", by_key[[ "TPE1", 1 ]][:next_bus_time]
    assert_equal "last_passed", by_key[[ "TPE2", 0 ]][:status]
  end

  class FailingClient
    def configured? = true

    def get_json(*, **)
      raise Transit::TdxClient::QuotaError, "TDX paused"
    end
  end

  test "serves the last stops marked stale while TDX fails" do
    store = ActiveSupport::Cache::MemoryStore.new
    original = Rails.method(:cache)
    Rails.define_singleton_method(:cache) { store }

    build([ { "StopUID" => "TPE1", "Direction" => 0, "EstimateTime" => 60, "StopStatus" => 0 } ]).call
    travel(Transit::BusRouteArrivalsQuery::CACHE_TTL + 1.second) do
      payload = Transit::BusRouteArrivalsQuery.new(route_id: ROUTE["id"], client: FailingClient.new, route: ROUTE.dup).call
      assert payload[:stale]
      assert_equal [ "TPE1" ], payload[:stops].map { |stop| stop[:stop_uid] }
    end

    store.clear
    payload = Transit::BusRouteArrivalsQuery.new(route_id: ROUTE["id"], client: FailingClient.new, route: ROUTE.dup).call
    assert_equal "TDX paused", payload[:error]
  ensure
    Rails.define_singleton_method(:cache, original) if original
  end
end
