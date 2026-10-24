# frozen_string_literal: true

module Transit
  # Live ETA for every stop of one bus route (TDX EstimatedTimeOfArrival).
  class BusRouteArrivalsQuery
    CLOCK_ZONE = ActiveSupport::TimeZone["Taipei"]
    CACHE_TTL = 45.seconds
    STALE_TTL = 10.minutes

    # TDX StopStatus: 0 normal, 1 not departed, 2 skipped (traffic control),
    # 3 last bus passed, 4 no service today.
    STATUSES = { 0 => "normal", 1 => "not_departed", 2 => "skipped", 3 => "last_passed", 4 => "no_service" }.freeze

    def initialize(route_id:, client: nil, route: nil)
      @route = route || RouteCatalog.find(route_id.to_s)
      @client = client || Transit::TdxClient.new
    end

    def call
      return error_payload("unknown_route") unless @route && @route["city_id"].present?

      @city = Geojson::BusCatalog.find(@route["city_id"])
      return error_payload("unknown_city") unless @city
      return error_payload("tdx_unconfigured") unless @client.configured?

      result = Transit::StaleCache.fetch(cache_key, expires_in: CACHE_TTL, stale_for: STALE_TTL) { build_stops }
      return error_payload(result.error) if result.value.nil?

      payload = { route_id: @route["id"], at: CLOCK_ZONE.now.iso8601, stops: result.value }
      payload[:stale] = true if result.stale?
      payload
    end

    private

    def build_stops
      rows = candidate_names.lazy.map { |name| fetch_rows(name) }.find(&:present?) || []
      best = {}
      rows.each do |row|
        stop = serialize(row)
        next unless stop

        key = [ stop[:stop_uid], stop[:direction] ]
        best[key] = stop if better?(stop, best[key])
      end
      best.values
    end

    def cache_key
      [ "bus_route_arrivals/v1", @route["id"] ]
    end

    def error_payload(error)
      { route_id: @route&.dig("id"), error: error, stops: [] }
    end

    def candidate_names
      names = [ @route["ref"].to_s ]
      names << @route["ref"].to_s.sub(/[A-J]\z/i, "") if @city.kind == :intercity
      names.uniq.reject(&:blank?)
    end

    def fetch_rows(name)
      path = if @city.kind == :intercity
        "v2/Bus/EstimatedTimeOfArrival/InterCity"
      else
        "v2/Bus/EstimatedTimeOfArrival/City/#{@city.tdx_city}"
      end
      filter = "RouteName/Zh_tw eq '#{name.gsub("'", "''")}'"
      Transit::ResponseDecoder.list(@client.get_json(path, query: { "$filter" => filter, "$format" => "JSON" }))
    end

    def serialize(row)
      stop_uid = row["StopUID"].presence
      return unless stop_uid

      seconds = row["EstimateTime"]&.to_i
      {
        stop_uid: stop_uid,
        stop_name: zh(row["StopName"]),
        direction: row["Direction"].to_i,
        estimate_seconds: seconds,
        status: STATUSES[row["StopStatus"].to_i] || "unknown",
        next_bus_time: clock(row["NextBusTime"])
      }.compact
    end

    # Several sub-routes can serve the same pole; keep the soonest real ETA.
    def better?(candidate, current)
      return true unless current
      return false if candidate[:estimate_seconds].nil?
      return true if current[:estimate_seconds].nil?

      candidate[:estimate_seconds] < current[:estimate_seconds]
    end

    def clock(value)
      return if value.blank?

      Time.iso8601(value.to_s).in_time_zone(CLOCK_ZONE).strftime("%H:%M")
    rescue ArgumentError
      nil
    end

    def zh(value)
      value.is_a?(Hash) ? value["Zh_tw"].presence : value.to_s.presence
    end
  end
end
