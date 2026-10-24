# frozen_string_literal: true

require "test_helper"

class Transit::TdxClientTest < ActiveSupport::TestCase
  TOKEN_BODY = { access_token: "tok", expires_in: 3600 }.to_json

  setup do
    @original_store = Transit::TdxClient.state_store
    Transit::TdxClient.state_store = ActiveSupport::Cache::MemoryStore.new
  end

  teardown do
    Transit::TdxClient.state_store = @original_store
  end

  def response(klass, code, body, headers = {})
    klass.new("1.1", code, "").tap do |res|
      res.instance_variable_set(:@body, body)
      res.instance_variable_set(:@read, true)
      headers.each { |name, value| res[name] = value }
    end
  end

  # Answers the token request, then the queued API responses in order.
  def stub_http(client, calls, queue, token: nil)
    test = self
    client.define_singleton_method(:http_request) do |uri, _request|
      calls << uri.to_s
      if uri.to_s.include?("openid-connect/token")
        token || test.response(Net::HTTPOK, "200", TOKEN_BODY)
      else
        queue.shift
      end
    end
    client.define_singleton_method(:sleep) { |_seconds| nil }
  end

  def build(queue, token: nil, **options)
    calls = []
    client = Transit::TdxClient.new(client_id: "id", client_secret: "secret", **options)
    stub_http(client, calls, queue, token: token)
    [ client, calls ]
  end

  test "a 429 opens the breaker and later page requests skip TDX" do
    client, calls = build([ response(Net::HTTPTooManyRequests, "429", "API rate limit exceeded", "Retry-After" => "60") ])

    assert_raises(Transit::TdxClient::QuotaError) { client.get_json("v2/Bus/EstimatedTimeOfArrival/City/Taipei") }
    assert Transit::TdxClient.breaker_open?
    assert_in_delta 60, Transit::TdxClient.breaker[:until] - Time.current.to_i, 2

    other, other_calls = build([ response(Net::HTTPOK, "200", "[]") ])
    assert_raises(Transit::TdxClient::QuotaError) { other.get_json("v2/Bus/EstimatedTimeOfArrival/City/Taipei") }
    assert_empty other_calls
    assert_equal 2, calls.length
  end

  test "batch clients ignore the breaker and retry 429s" do
    Transit::TdxClient.open_breaker!("test")
    client, = build([
      response(Net::HTTPTooManyRequests, "429", "API rate limit exceeded"),
      response(Net::HTTPOK, "200", '[{"a":1}]')
    ], ignore_breaker: true)

    assert_equal [ { "a" => 1 } ], client.get_json("v2/Bus/Route/City/Taipei")
  end

  test "a rejected key opens the breaker without retrying" do
    client, calls = build([], token: response(Net::HTTPBadRequest, "400", '{"error":"unauthorized_client","error_description":"Invalid client credentials"}'))

    assert_raises(Transit::TdxClient::QuotaError) { client.get_json("v2/Bus/Route/City/Taipei") }
    assert_equal 1, calls.length
    assert_match "rejected", Transit::TdxClient.breaker[:reason]
  end

  test "breaker durations escalate without Retry-After" do
    first = Transit::TdxClient.open_breaker!("one")
    Transit::TdxClient.state_store.delete(Transit::TdxClient::BREAKER_KEY)
    second = Transit::TdxClient.open_breaker!("two")

    assert_in_delta 10.minutes, first - Time.current, 5
    assert_in_delta 20.minutes, second - Time.current, 5

    Transit::TdxClient.close_breaker!
    refute Transit::TdxClient.breaker_open?
  end

  test "counts requests per dataset" do
    client, = build([ response(Net::HTTPOK, "200", "[]"), response(Net::HTTPOK, "200", "[]") ])
    client.get_json("v2/Bus/EstimatedTimeOfArrival/City/Taipei")
    client.get_json("v2/Bus/EstimatedTimeOfArrival/City/NewTaipei")

    assert_equal({ "token" => 1, "v2/Bus/EstimatedTimeOfArrival" => 2 }, Transit::TdxClient.usage)
  end
end
