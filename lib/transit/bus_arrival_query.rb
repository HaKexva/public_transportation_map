# frozen_string_literal: true

module Transit
  # Live / near-live bus arrivals from TDX EstimatedTimeOfArrival (N1).
  class BusArrivalQuery
    CLOCK_ZONE = ActiveSupport::TimeZone["Taipei"]
    MAX_ROWS = 24
    CACHE_TTL = 20.seconds

    StopStatus = {
      0 => :arriving,
      1 => :not_departed,
      2 => :en_route,
      3 => :no_service,
      4 => :not_departed,
      5 => :en_route
    }.freeze

    def initialize(city_id:, stop_uid:, route_name: nil, client: nil)
      @city = Geojson::BusCatalog.find(city_id)
      @stop_uid = stop_uid.to_s.strip
      @route_name = route_name.to_s.strip.presence
      @client = client || Transit::TdxClient.new
    end

    def call
      return empty_payload(error: "missing_stop") if @stop_uid.blank?
      return empty_payload(error: "unknown_city") unless @city
      return empty_payload(error: "tdx_unconfigured") unless @client.configured?

      rows = Rails.cache.fetch(cache_key, expires_in: CACHE_TTL) { fetch_rows }
      arrivals = Array(rows).filter_map { |row| serialize(row) }
        .sort_by { |row| [ row[:sort_seconds], row[:route_name].to_s, row[:direction].to_i ] }
        .first(MAX_ROWS)

      {
        at: CLOCK_ZONE.now.iso8601,
        city_id: @city.id,
        stop_uid: @stop_uid,
        arrivals: arrivals
      }
    rescue Transit::TdxClient::Error => error
      empty_payload(error: error.message)
    end

    private

    def cache_key
      [ "bus_arrivals/v1", @city.id, @stop_uid, @route_name ]
    end

    def empty_payload(error: nil)
      payload = {
        at: CLOCK_ZONE.now.iso8601,
        city_id: @city&.id,
        stop_uid: @stop_uid,
        arrivals: []
      }
      payload[:error] = error if error.present?
      payload
    end

    def fetch_rows
      path = eta_path
      query = {
        "$filter" => odata_filter,
        "$orderby" => "EstimateTime",
        "$top" => 40,
        "$format" => "JSON"
      }
      Transit::ResponseDecoder.list(@client.get_json(path, query: query))
    end

    def eta_path
      if @city.kind == :intercity
        "v2/Bus/EstimatedTimeOfArrival/InterCity"
      else
        "v2/Bus/EstimatedTimeOfArrival/City/#{@city.tdx_city}"
      end
    end

    def odata_filter
      clauses = [ "StopUID eq '#{escape_odata(@stop_uid)}'" ]
      if @route_name
        clauses << "RouteName/Zh_tw eq '#{escape_odata(@route_name)}'"
      end
      clauses.join(" and ")
    end

    def escape_odata(value)
      value.to_s.gsub("'", "''")
    end

    def serialize(row)
      estimate = row["EstimateTime"]
      status_code = row["StopStatus"]
      status = StopStatus[status_code.to_i] || :unknown
      seconds = estimate.nil? ? nil : estimate.to_i
      return if seconds.nil? && status == :no_service

      route_name = zh_name(row["RouteName"]).presence || row["RouteName"].to_s
      destination = zh_name(row["DestinationStopName"]).presence ||
        zh_name(row["DestinationName"]).presence

      {
        route_name: route_name,
        route_id: row["RouteUID"].presence || row["RouteID"].presence,
        direction: row["Direction"],
        destination_name: destination,
        estimate_seconds: seconds,
        estimate_minutes: seconds.nil? ? nil : (seconds / 60.0).round(1),
        stop_status: status_code,
        status: status.to_s,
        plate: row["PlateNumb"].presence,
        sort_seconds: seconds.nil? ? 1_000_000 + status_code.to_i : [ seconds, 0 ].max
      }
    end

    def zh_name(value)
      case value
      when Hash then value["Zh_tw"].presence || value[:Zh_tw].presence
      else value.to_s.presence
      end
    end
  end
end
