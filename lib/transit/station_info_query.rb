# frozen_string_literal: true

module Transit
  # Station exits / accessibility extras from TDX StationExit (metro + TRA).
  class StationInfoQuery
    CACHE_TTL = 12.hours
    METRO_EXIT_SYSTEMS = %w[TRTC KRTC TYMC TMRT NTMC].freeze

    def initialize(station_ref:, route_id: nil, client: nil)
      @station_ref = station_ref.to_s.strip
      @route_id = route_id.to_s.strip.presence
      @client = client || Transit::TdxClient.new
    end

    def call
      refs = station_refs
      return empty_payload(error: "missing_ref") if refs.empty?
      return empty_payload(error: "tdx_unconfigured") unless @client.configured?

      route = @route_id ? RouteCatalog.find(@route_id) : nil
      system_id = route&.dig("system_id").to_s

      exits =
        case system_id
        when "tra"
          refs.flat_map { |ref| fetch_tra_exits(ref) }
        when "hsr", "sugar_railway", "ferry", ""
          []
        else
          refs.flat_map { |ref| fetch_metro_exits(ref, system_id) }
        end

      exits = dedupe_exits(exits)

      {
        station_ref: @station_ref,
        route_id: @route_id,
        system_id: system_id.presence,
        exits: exits,
        accessibility: accessibility_summary(exits),
        source: exits.any? ? "tdx_station_exit" : nil
      }
    rescue Transit::TdxClient::Error => error
      empty_payload(error: error.message)
    end

    private

    def empty_payload(error: nil)
      payload = {
        station_ref: @station_ref,
        route_id: @route_id,
        exits: [],
        accessibility: {
          elevator: false,
          escalator: false,
          stair: false
        }
      }
      payload[:error] = error if error.present?
      payload
    end

    def station_refs
      @station_ref.to_s.split(";").map { |part| part.strip }.reject(&:blank?).map do |part|
        part.split("-").first
      end.uniq
    end

    def fetch_metro_exits(ref, system_id)
      systems = MetroSystemRegistry.tdx_rail_systems_for_route(@route_id)
      systems = MetroSystemRegistry.tdx_rail_systems_for_system(system_id) if systems.empty?
      systems = METRO_EXIT_SYSTEMS if systems.empty?

      systems.flat_map do |rail_system|
        next [] unless METRO_EXIT_SYSTEMS.include?(rail_system)

        rows = cached_exits("metro", rail_system, ref) do
          path = "v2/Rail/Metro/StationExit/#{rail_system}"
          query = {
            "$filter" => "StationID eq '#{escape_odata(ref)}'",
            "$format" => "JSON"
          }
          Transit::ResponseDecoder.list(@client.get_json(path, query: query))
        end
        rows.map { |row| serialize_exit(row, rail_system) }
      end
    end

    def fetch_tra_exits(ref)
      candidates = tra_station_id_candidates(ref)
      candidates.flat_map do |station_id|
        rows = cached_exits("tra", "TRA", station_id) do
          path = "v3/Rail/TRA/StationExit"
          query = {
            "$filter" => "StationID eq '#{escape_odata(station_id)}'",
            "$format" => "JSON"
          }
          Transit::ResponseDecoder.list(@client.get_json(path, query: query))
        end
        rows.map { |row| serialize_exit(row, "TRA") }
      end
    end

    def tra_station_id_candidates(ref)
      digits = ref.to_s.gsub(/\D/, "")
      return [ ref ] if digits.blank?

      [ digits, digits.rjust(4, "0") ].uniq
    end

    def cached_exits(kind, system, station_id)
      key = [ "station_info/exits/v1", kind, system, station_id ]
      Rails.cache.fetch(key, expires_in: CACHE_TTL) { yield }
    end

    def serialize_exit(row, rail_system)
      name = ResponseDecoder.localized_name(row["ExitName"]).presence ||
        row["ExitID"].presence ||
        row["ExitName"].to_s
      location = ResponseDecoder.localized_name(row["LocationDescription"]).presence ||
        row["LocationDescription"].to_s.presence

      position = row["ExitPosition"] || {}
      {
        id: [ rail_system, row["StationID"], row["ExitID"] ].compact.join(":"),
        exit_id: row["ExitID"].presence,
        name: name,
        location: location,
        stair: truthy?(row["Stair"]),
        escalator: truthy?(row["Escalator"]),
        elevator: truthy?(row["Elevator"]),
        lon: position["PositionLon"],
        lat: position["PositionLat"]
      }
    end

    def truthy?(value)
      value == true || value.to_s.downcase == "true" || value.to_s == "1"
    end

    def dedupe_exits(exits)
      seen = {}
      exits.each do |exit|
        key = exit[:id].presence || "#{exit[:name]}:#{exit[:lon]}:#{exit[:lat]}"
        seen[key] ||= exit
      end
      seen.values.sort_by { |exit| [ exit[:name].to_s, exit[:exit_id].to_s ] }
    end

    def accessibility_summary(exits)
      {
        elevator: exits.any? { |exit| exit[:elevator] },
        escalator: exits.any? { |exit| exit[:escalator] },
        stair: exits.any? { |exit| exit[:stair] },
        exit_count: exits.length
      }
    end

    def escape_odata(value)
      value.to_s.gsub("'", "''")
    end
  end
end
