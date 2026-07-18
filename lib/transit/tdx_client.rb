# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

module Transit
  class TdxClient
    class Error < StandardError; end
    class ConfigurationError < Error; end
    class RequestError < Error; end

    TOKEN_URL = "https://tdx.transportdata.tw/auth/realms/TDXConnect/protocol/openid-connect/token"
    API_BASE = "https://tdx.transportdata.tw/api/basic"

    DEFAULT_PAGE_SIZE = 1_000
    MAX_RETRIES = 5
    RETRYABLE_CODES = %w[429 503].freeze
    REQUEST_DELAY = 0.15

    def self.configured?
      new.configured?
    end

    def initialize(client_id: nil, client_secret: nil)
      @client_id = client_id.presence || ENV["TDX_CLIENT_ID"].presence || credentials_client_id
      @client_secret = client_secret.presence || ENV["TDX_CLIENT_SECRET"].presence || credentials_client_secret
      @access_token = nil
      @token_expires_at = Time.at(0)
    end

    def configured?
      @client_id.present? && @client_secret.present?
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
        sleep(REQUEST_DELAY)
      end

      records
    end

    def get_json(path, query: {})
      uri = URI.join("#{API_BASE}/", path.delete_prefix("/"))
      uri.query = URI.encode_www_form(query) if query.present?

      request = Net::HTTP::Get.new(uri)
      request["Authorization"] = "Bearer #{access_token}"
      request["Accept"] = "application/json"

      response = request_with_retries(uri, request)
      JSON.parse(response.body)
    end

    private

    def credentials_client_id
      Rails.application.credentials.dig(:tdx, :client_id)
    end

    def credentials_client_secret
      Rails.application.credentials.dig(:tdx, :client_secret)
    end

    def access_token
      return @access_token if @access_token.present? && Time.current < @token_expires_at

      uri = URI(TOKEN_URL)
      request = Net::HTTP::Post.new(uri)
      request.set_form_data(
        grant_type: "client_credentials",
        client_id: @client_id,
        client_secret: @client_secret
      )

      response = request_with_retries(uri, request)
      unless response.is_a?(Net::HTTPSuccess)
        raise RequestError, "TDX token request failed (#{response.code}): #{response.body.to_s.truncate(200)}"
      end

      body = JSON.parse(response.body)
      @access_token = body.fetch("access_token")
      @token_expires_at = Time.current + body.fetch("expires_in", 86_400).to_i.seconds - 60.seconds
      @access_token
    end

    def request_with_retries(uri, request)
      attempt = 0

      loop do
        response = http_request(uri, request)
        return response if response.is_a?(Net::HTTPSuccess)
        break unless RETRYABLE_CODES.include?(response.code) && attempt < MAX_RETRIES

        attempt += 1
        sleep(2**attempt)
      end

      raise RequestError, "TDX #{response.code} for #{uri}: #{response.body.to_s.truncate(200)}"
    end

    def http_request(uri, request)
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 15, read_timeout: 120) do |http|
        http.request(request)
      end
    end
  end
end
