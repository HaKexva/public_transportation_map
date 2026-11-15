# frozen_string_literal: true

module Transit
  # Copies TDX StationExit / StationFacility into station_infos: one paged
  # fetch per rail system instead of one request per station page view.
  #
  #   bin/rails transit:refresh_station_info
  module StationInfoImporter
    SYSTEMS = {
      "TRA" => { exits: "v3/Rail/TRA/StationExit", facilities: "v3/Rail/TRA/StationFacility" },
      **StationInfoQuery::METRO_SYSTEMS.to_h do |system|
        [ system, { exits: "v2/Rail/Metro/StationExit/#{system}", facilities: "v2/Rail/Metro/StationFacility/#{system}" } ]
      end
    }.freeze

    module_function

    # Systems whose download fails keep their previous rows.
    def import!(client: TdxClient.new(ignore_breaker: true), systems: SYSTEMS.keys)
      stored = 0
      failed = []
      systems.each do |system|
        paths = SYSTEMS.fetch(system)
        exits = client.fetch_all(paths[:exits])
        facilities = client.fetch_all(paths[:facilities])
        next failed << system if exits.empty? && facilities.empty?

        stored += store_system!(system, exits:, facilities:)
      rescue TdxClient::Error => error
        Rails.logger.warn("[StationInfoImporter] #{system}: #{error.message}")
        failed << system
      end
      { stations: stored, failed: }
    end

    def store_system!(system, exits:, facilities:, fetched_at: Time.current)
      by_station = Hash.new { |hash, id| hash[id] = { exits: [], facilities: [] } }
      exits.each { |row| by_station[row["StationID"].to_s][:exits] << row }
      facilities.each { |row| by_station[row["StationID"].to_s][:facilities] << row }
      by_station.delete("")

      rows = by_station.map do |station_id, data|
        { system:, station_id:, **data, fetched_at:, created_at: fetched_at, updated_at: fetched_at }
      end
      StationInfo.transaction do
        StationInfo.where(system:).where.not(station_id: by_station.keys).delete_all
        StationInfo.upsert_all(rows, unique_by: %i[system station_id], update_only: %i[exits facilities fetched_at]) if rows.any?
      end
      rows.size
    end
  end
end
