# frozen_string_literal: true

module Transit
  # Live / near-live bus arrivals from TDX EstimatedTimeOfArrival (N1).
  class BusArrivalQuery
    CLOCK_ZONE = ActiveSupport::TimeZone["Taipei"]
    MAX_ROWS = 40
    CACHE_TTL = 45.seconds
    STALE_TTL = 10.minutes

    StopStatus = {
      0 => :arriving,
      1 => :not_departed,
      2 => :en_route,
      3 => :no_service,
      4 => :not_departed,
      5 => :en_route
    }.freeze

    # stop_name + route_names widen the board to every route serving the pole:
    # TDX gives each route its own StopUID, so filtering by StopUID alone only
    # ever returns the clicked route.
    # stop_uids pins the board to one stop group (every route's StopUID at it),
    # so same-name groups across the street don't bleed into each other.
    def initialize(city_id:, stop_uid:, route_name: nil, stop_name: nil, route_names: nil, city_ids: nil, stop_uids: nil, client: nil)
      @city = Geojson::BusCatalog.find(city_id)
      @stop_uids = Array(stop_uids).map { |uid| uid.to_s.strip }.reject(&:blank?).uniq.first(60)
      @stop_uid = stop_uid.to_s.strip.presence || @stop_uids.first.to_s
      @route_name = route_name.to_s.strip.presence
      @stop_name = stop_name.to_s.strip.presence
      @route_names = Array(route_names).map { |name| name.to_s.strip }.reject(&:blank?).uniq
      @extra_cities = Array(city_ids).filter_map { |id| Geojson::BusCatalog.find(id) }
      @client = client || Transit::TdxClient.new
    end

    def call
      return empty_payload(error: "missing_stop") if @stop_uid.blank?
      return empty_payload(error: "unknown_city") unless @city
      return empty_payload(error: "tdx_unconfigured") unless @client.configured?

      result = Transit::StaleCache.fetch(cache_key, expires_in: CACHE_TTL, stale_for: STALE_TTL) { fetch_rows }
      return empty_payload(error: result.error) if result.value.nil?

      arrivals = Array(result.value).filter_map { |row| serialize(row) }
        .sort_by { |row| [ row[:sort_seconds], row[:route_name].to_s, row[:direction].to_i ] }
        .first(MAX_ROWS)

      payload = {
        at: CLOCK_ZONE.now.iso8601,
        city_id: @city.id,
        stop_uid: @stop_uid,
        arrivals: arrivals
      }
      payload[:stale] = true if result.stale?
      payload
    end

    private

    def cache_key
      [ "bus_arrivals/v3", @city.id, @stop_uid, @route_name, @stop_name, @route_names.sort, board_cities.map(&:id), @stop_uids.sort ]
    end

    def station_board?
      @stop_name.present? && @route_name.blank?
    end

    def group_board?
      @stop_uids.any?
    end

    def board_cities
      ([ @city ] + @extra_cities).uniq(&:id).first(3)
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
      return fetch_group_rows if group_board?
      return fetch_station_rows if station_board?

      query = {
        "$filter" => odata_filter,
        "$orderby" => "EstimateTime",
        "$top" => 40,
        "$format" => "JSON"
      }
      Transit::ResponseDecoder.list(@client.get_json(eta_path(@city), query: query))
    end

    def fetch_station_rows
      allowed = @route_names.to_set
      filter = "StopName/Zh_tw eq '#{escape_odata(@stop_name)}' or StopUID eq '#{escape_odata(@stop_uid)}'"
      board_cities.flat_map do |city|
        rows = Transit::ResponseDecoder.list(
          @client.get_json(eta_path(city), query: { "$filter" => filter, "$top" => 200, "$format" => "JSON" })
        )
        rows.select do |row|
          row["StopUID"].to_s == @stop_uid ||
            allowed.empty? ||
            allowed.include?(zh_name(row["RouteName"]).to_s)
        end
      end
    end

    def fetch_group_rows
      filter = @stop_uids.map { |uid| "StopUID eq '#{escape_odata(uid)}'" }.join(" or ")
      board_cities.flat_map do |city|
        Transit::ResponseDecoder.list(
          @client.get_json(eta_path(city), query: { "$filter" => filter, "$top" => 300, "$format" => "JSON" })
        )
      end
    end

    def eta_path(city)
      if city.kind == :intercity
        "v2/Bus/EstimatedTimeOfArrival/InterCity"
      else
        "v2/Bus/EstimatedTimeOfArrival/City/#{city.tdx_city}"
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
