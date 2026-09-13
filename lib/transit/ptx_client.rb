# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

module Transit
  # MOTC PTX v2 — public read API (no OAuth). Used when TDX credentials are
  # unavailable for static Shape / StopOfRoute imports.
  class PtxClient
    class Error < StandardError; end
    class RequestError < Error; end

    API_BASE = "https://ptx.transportdata.tw/MOTC"

    DEFAULT_PAGE_SIZE = 1_000
    MAX_RETRIES = 5
    RETRYABLE_CODES = %w[429 503].freeze
    REQUEST_DELAY = 0.15

    def fetch_all(path, query: {}, page_size: DEFAULT_PAGE_SIZE)
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
      request["Accept"] = "application/json"

      response = request_with_retries(uri, request)
      JSON.parse(response.body)
    end

    private

    def request_with_retries(uri, request)
      attempt = 0
      response = nil

      loop do
        response = http_request(uri, request)
        return response if response.is_a?(Net::HTTPSuccess)
        break unless RETRYABLE_CODES.include?(response.code) && attempt < MAX_RETRIES

        attempt += 1
        sleep(2**attempt)
      end

      code = response&.code || "nil"
      body = response&.body.to_s.truncate(200)
      raise RequestError, "PTX #{code} for #{uri}: #{body}"
    end

    def http_request(uri, request)
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 15, read_timeout: 120) do |http|
        http.request(request)
      end
    end
  end
end
