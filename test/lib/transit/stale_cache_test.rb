# frozen_string_literal: true

require "test_helper"

class Transit::StaleCacheTest < ActiveSupport::TestCase
  setup do
    @cache = ActiveSupport::Cache::MemoryStore.new
  end

  def fetch(&block)
    Transit::StaleCache.fetch("feed", expires_in: 1.minute, stale_for: 10.minutes, cache: @cache, &block)
  end

  test "serves the last good value marked stale when the feed fails" do
    assert_equal [ 1 ], fetch { [ 1 ] }.value

    travel 2.minutes do
      result = fetch { raise Transit::TdxClient::QuotaError, "paused" }
      assert_equal [ 1 ], result.value
      assert result.stale?
      assert_equal "paused", result.error
    end
  end

  test "remembers a failure so the feed is not retried every request" do
    calls = 0
    2.times { fetch { calls += 1; raise Transit::TdxClient::RequestError, "boom" } }
    assert_equal 1, calls

    travel(Transit::StaleCache::FAILURE_TTL + 1.second) do
      assert_equal [ 2 ], fetch { calls += 1; [ 2 ] }.value
    end
    assert_equal 2, calls
  end

  test "nil value without anything cached" do
    result = fetch { raise Transit::TdxClient::RequestError, "boom" }
    assert_nil result.value
    assert result.stale?
  end
end
