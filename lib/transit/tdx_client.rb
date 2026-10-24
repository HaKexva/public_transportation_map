# frozen_string_literal: true

require "digest"
require "net/http"
require "json"
require "uri"

module Transit
  class TdxClient
    class Error < StandardError; end
    class ConfigurationError < Error; end
    class RequestError < Error; end
    # TDX is refusing us (quota / rate limit / key rejected); the breaker is open.
    class QuotaError < RequestError; end

    TOKEN_URL = "https://tdx.transportdata.tw/auth/realms/TDXConnect/protocol/openid-connect/token"
    API_BASE = "https://tdx.transportdata.tw/api/basic"

    DEFAULT_PAGE_SIZE = 1_000
    MAX_RETRIES = 5
    RETRYABLE_CODES = %w[429 503].freeze

    BREAKER_KEY = "tdx_breaker/v1"
    STRIKES_KEY = "tdx_breaker/v1/strikes"
    BREAKER_STEPS = [ 10.minutes, 20.minutes, 30.minutes ].freeze
    STRIKE_MEMORY = 2.hours
    MAX_REQUESTS_PER_SECOND = 4
    USAGE_RETENTION = 8.days

    class << self
      attr_writer :state_store

      def configured?
        new.configured?
      end

      # Breaker, rate-limit and usage state shared by every process. A
      # per-process (memory) or no-op (null) Rails.cache cannot share it, so
      # fall back to a small file store under tmp/.
      def state_store
        @state_store ||= if Rails.env.test?
          ActiveSupport::Cache::MemoryStore.new
        elsif Rails.cache.is_a?(ActiveSupport::Cache::MemoryStore) || Rails.cache.is_a?(ActiveSupport::Cache::NullStore)
          ActiveSupport::Cache::FileStore.new(Rails.root.join("tmp/cache/tdx_state"))
        else
          Rails.cache
        end
      end

      # { until: Time, reason: String } while TDX calls are suspended.
      def breaker
        state = state_store.read(BREAKER_KEY)
        state if state.is_a?(Hash) && state[:until].to_i > Time.current.to_i
      end

      def breaker_open?
        breaker.present?
      end

      def open_breaker!(reason, retry_after: nil)
        duration = if retry_after.to_f.positive?
          retry_after.to_f.seconds
        else
          strikes = state_store.increment(STRIKES_KEY, 1, expires_in: STRIKE_MEMORY).to_i
          BREAKER_STEPS[[ strikes, 1 ].max - 1] || BREAKER_STEPS.last
        end
        until_time = Time.current + duration
        state_store.write(BREAKER_KEY, { until: until_time.to_i, reason: reason.to_s.truncate(200) }, expires_in: duration)
        Rails.logger.warn("[TDX] breaker open until #{until_time.strftime('%H:%M:%S')}: #{reason.to_s.truncate(120)}")
        until_time
      end

      def close_breaker!
        state_store.delete(BREAKER_KEY)
        state_store.delete(STRIKES_KEY)
      end

      def usage_key(date, name = nil)
        [ "tdx_usage/v1", date.to_s, name ].compact.join("/")
      end

      # { "v2/Bus/EstimatedTimeOfArrival/City" => 120, ... } for one day.
      def usage(date = Date.current)
        Array(state_store.read(usage_key(date, "index"))).index_with do |name|
          state_store.read(usage_key(date, name)).to_i
        end
      end

      def record_usage!(name)
        date = Date.current
        count = state_store.increment(usage_key(date, name), 1, expires_in: USAGE_RETENTION)
        return unless count.to_i == 1

        index = Array(state_store.read(usage_key(date, "index")))
        state_store.write(usage_key(date, "index"), (index | [ name ]), expires_in: USAGE_RETENTION)
      end

      # Usage is grouped by dataset, dropping the city / operator / query.
      def usage_name(path)
        segments = path.to_s.delete_prefix("/").split("?").first.to_s.split("/")
        cut = segments.index { |segment| %w[City InterCity Streaming].include?(segment) }
        (cut ? segments.first(cut) : segments.first(4)).join("/")
      end
    end

    # max_wait: seconds a request may spend sleeping on 429/503 retries before
    # giving up (nil = keep retrying). TDX's per-minute quota answers 429 with
    # Retry-After of up to a minute, too long to hold a page request.
    # ignore_breaker: batch jobs / rake tasks keep going (and keep retrying
    # 429s) while page requests are suspended by the breaker.
    def initialize(client_id: nil, client_secret: nil, max_wait: nil, ignore_breaker: false)
      @client_id = client_id.presence || ENV["TDX_CLIENT_ID"].presence || credentials_client_id
      @client_secret = client_secret.presence || ENV["TDX_CLIENT_SECRET"].presence || credentials_client_secret
      @max_wait = max_wait
      @ignore_breaker = ignore_breaker
      @access_token = nil
      @token_expires_at = Time.at(0)
    end

    def configured?
      @client_id.present? && @client_secret.present?
    end

    # Hits the token endpoint before a long import. Dead credentials raise
    # RequestError here instead of after hours of timetable writes.
    def probe!
      raise ConfigurationError, "TDX_CLIENT_ID and TDX_CLIENT_SECRET are required" unless configured?

      access_token
      true
    end

    def fetch_all(path, query: {}, page_size: DEFAULT_PAGE_SIZE)
      raise ConfigurationError, "TDX_CLIENT_ID and TDX_CLIENT_SECRET are required" unless configured?

      records = []
      skip = 0

      loop do
        page_query = query.merge("$top" => page_size, "$skip" => skip, "$format" => "JSON")
        payload = get_json(path, query: page_query)
        batch = ResponseDecoder.list(payload)
        break if batch.empty?

        records.concat(batch)
        break if batch.length < page_size

        skip += page_size
      end

      records
    end

    def get_json(path, query: {})
      check_breaker!
      uri = URI.join("#{API_BASE}/", path.delete_prefix("/"))
      uri.query = URI.encode_www_form(query) if query.present?

      request = Net::HTTP::Get.new(uri)
      request["Authorization"] = "Bearer #{access_token}"
      request["Accept"] = "application/json"

      response = request_with_retries(uri, request, usage: self.class.usage_name(path))
      JSON.parse(response.body)
    end

    private

    def credentials_client_id
      Rails.application.credentials.dig(:tdx, :client_id)
    end

    def credentials_client_secret
      Rails.application.credentials.dig(:tdx, :client_secret)
    end

    # Tokens last a day and TDX rate-limits the token endpoint too, so every
    # client (and process, via Rails.cache) shares one.
    def access_token
      return @access_token if @access_token.present? && Time.current < @token_expires_at

      cached = Rails.cache.read(token_cache_key)
      if cached.is_a?(Hash) && cached[:expires_at].to_i > Time.current.to_i
        @token_expires_at = Time.zone.at(cached[:expires_at])
        return @access_token = cached[:token]
      end

      check_breaker!
      fetch_access_token.tap do |token|
        Rails.cache.write(token_cache_key, { token:, expires_at: @token_expires_at.to_i }, expires_at: @token_expires_at)
      end
    end

    def check_breaker!
      return if @ignore_breaker

      state = self.class.breaker
      return unless state

      raise QuotaError, "TDX paused until #{Time.zone.at(state[:until]).strftime('%H:%M:%S')}: #{state[:reason]}"
    end

    # At most MAX_REQUESTS_PER_SECOND across every process sharing the store.
    # Wall clock from the OS so a frozen Time (travel_to) cannot stall it.
    def throttle!
      loop do
        now = Process.clock_gettime(Process::CLOCK_REALTIME)
        count = self.class.state_store.increment("tdx_rate/v1/#{now.to_i}", 1, expires_in: 5.seconds)
        return if count.nil? || count <= MAX_REQUESTS_PER_SECOND

        sleep([ (now.to_i + 1) - now, 0.05 ].max)
      end
    end

    def token_cache_key
      [ "tdx_access_token/v1", Digest::SHA256.hexdigest(@client_id.to_s) ]
    end

    def fetch_access_token
      uri = URI(TOKEN_URL)
      request = Net::HTTP::Post.new(uri)
      request.set_form_data(
        grant_type: "client_credentials",
        client_id: @client_id,
        client_secret: @client_secret
      )

      response = request_with_retries(uri, request, usage: "token")
      unless response.is_a?(Net::HTTPSuccess)
        raise RequestError, "TDX token request failed (#{response.code}): #{response.body.to_s.truncate(200)}"
      end

      body = JSON.parse(response.body)
      @access_token = body.fetch("access_token")
      @token_expires_at = Time.current + body.fetch("expires_in", 86_400).to_i.seconds - 60.seconds
      @access_token
    end

    def request_with_retries(uri, request, usage: nil)
      attempt = 0
      waited = 0.0
      response = nil

      loop do
        throttle!
        response = http_request(uri, request)
        self.class.record_usage!(usage) if usage
        return response if response.is_a?(Net::HTTPSuccess)

        if rejected_key?(response)
          self.class.open_breaker!("TDX rejected the API key (#{response.code})")
          raise QuotaError, "TDX #{response.code} for #{uri}: #{response.body.to_s.truncate(200)}"
        end
        if response.code == "429"
          self.class.open_breaker!("TDX 429 #{response.body.to_s.squish.truncate(80)}", retry_after: response["Retry-After"])
          raise QuotaError, "TDX 429 for #{uri}: #{response.body.to_s.truncate(200)}" unless @ignore_breaker
        end
        break unless RETRYABLE_CODES.include?(response.code) && attempt < MAX_RETRIES

        attempt += 1
        delay = [ response["Retry-After"].to_f, 2**attempt ].max
        break if @max_wait && waited + delay > @max_wait

        sleep(delay)
        waited += delay
      end

      code = response&.code || "nil"
      body = response&.body.to_s.truncate(200)
      raise RequestError, "TDX #{code} for #{uri}: #{body}"
    end

    # Bad / disabled credentials: retrying only burns more of the quota.
    def rejected_key?(response)
      return false unless %w[400 401 403].include?(response.code)

      body = response.body.to_s
      body.include?("unauthorized_client") || body.include?("invalid_client") || body.include?("Invalid client credentials")
    end

    def http_request(uri, request)
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 15, read_timeout: 120) do |http|
        http.request(request)
      end
    end
  end
end
