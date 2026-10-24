# frozen_string_literal: true

module Transit
  # Cache for live TDX feeds that keeps the last good value around and
  # remembers failures, so an outage costs one TDX call per FAILURE_TTL
  # instead of one per page request.
  module StaleCache
    FAILURE_TTL = 30.seconds
    FAILURES = [ TdxClient::Error, JSON::ParserError, SocketError, Timeout::Error, SystemCallError ].freeze

    Result = Struct.new(:value, :stale, :error, keyword_init: true) do
      def stale? = stale
    end

    module_function

    def fetch(key, expires_in:, stale_for:, cache: Rails.cache, failure_ttl: FAILURE_TTL)
      key = ActiveSupport::Cache.expand_cache_key(key)
      fresh = cache.read(key)
      return Result.new(value: fresh, stale: false) unless fresh.nil?

      if (failure = cache.read("#{key}/failed"))
        return Result.new(value: cache.read("#{key}/stale"), stale: true, error: failure)
      end

      begin
        value = yield
        cache.write(key, value, expires_in: expires_in)
        cache.write("#{key}/stale", value, expires_in: stale_for)
        Result.new(value: value, stale: false)
      rescue *FAILURES => e
        Rails.logger.warn("[StaleCache] #{key}: #{e.class}: #{e.message.to_s.truncate(160)}")
        cache.write("#{key}/failed", e.message, expires_in: failure_ttl)
        Result.new(value: cache.read("#{key}/stale"), stale: true, error: e.message)
      end
    end
  end
end
