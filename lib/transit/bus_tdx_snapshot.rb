# frozen_string_literal: true

require "json"

module Transit
  # Daily copy of TDX bus Schedule / Route / RouteFare in bus_route_timetables,
  # one row per route name, so route details never wait on TDX (whose
  # per-minute quota turns page-time lookups into 30–60 s of 429 back-off).
  #
  #   bin/rails geojson:bus_service_days   # also refreshes this snapshot
  module BusTdxSnapshot
    LEGACY_ROOT = Rails.root.join("tmp/tdx_bus")

    module_function

    # Replaces one city's rows; route names TDX no longer lists are removed.
    def write_city!(city_id, schedules:, routes:, fares:, fetched_at: Time.current)
      by_name = Hash.new { |hash, name| hash[name] = { "schedules" => [], "routes" => [], "fares" => [] } }
      schedules.each { |row| by_name[zh(row["RouteName"])]["schedules"] << row }
      routes.each { |row| by_name[zh(row["RouteName"])]["routes"] << row }
      fares.each { |row| by_name[zh(row["RouteName"])]["fares"] << compact_fare(row) }
      by_name.delete("")

      rows = by_name.map do |name, data|
        { city_id: city_id.to_s, route_name: name, fetched_at:, created_at: fetched_at, updated_at: fetched_at, **data.symbolize_keys }
      end
      BusRouteTimetable.transaction do
        BusRouteTimetable.where(city_id: city_id.to_s).where.not(route_name: by_name.keys).delete_all
        BusRouteTimetable.upsert_all(rows, unique_by: %i[city_id route_name], update_only: %i[schedules routes fares fetched_at]) if rows.any?
      end
      rows.size
    end

    # { "schedules" => [...], "routes" => [...], "fares" => [...], "fetched_at" => ... }
    # for one TDX RouteName. Old rows are still served: a stale timetable beats none.
    def read(city_id, name)
      return nil if city_id.blank? || name.blank?

      row = BusRouteTimetable.find_by(city_id: city_id.to_s, route_name: name.to_s)
      return nil unless row

      { "schedules" => row.schedules, "routes" => row.routes, "fares" => row.fares, "fetched_at" => row.fetched_at.iso8601 }
    end

    # Seeds the table from the old one-file-per-route snapshot under tmp/tdx_bus.
    def import_files!(root: LEGACY_ROOT)
      Dir.glob(root.join("*")).select { |path| File.directory?(path) }.sum do |dir|
        city_id = File.basename(dir)
        rows = Dir.glob(File.join(dir, "*.json")).filter_map do |path|
          data = JSON.parse(File.read(path))
          next if data["name"].blank?

          fetched_at = Time.zone.parse(data["fetched_at"].to_s) || File.mtime(path)
          { city_id:, route_name: data["name"], schedules: Array(data["schedules"]), routes: Array(data["routes"]),
            fares: Array(data["fares"]), fetched_at:, created_at: Time.current, updated_at: Time.current }
        rescue JSON::ParserError
          nil
        end
        rows.each_slice(200) do |slice|
          BusRouteTimetable.upsert_all(slice, unique_by: %i[city_id route_name], update_only: %i[schedules routes fares fetched_at])
        end
        rows.size
      end
    end

    # Origin–destination fare matrices run to megabytes per route; the details
    # panel only shows their adult price range, so keep just its two ends.
    def compact_fare(row)
      %w[ODFares StageFares].each do |key|
        entries = Array(row[key])
        next if entries.empty?

        adult = entries.flat_map { |entry| Array(entry["Fares"]) }
          .select { |price| price["FareClass"].to_i == 1 && price["TicketType"].to_i == 1 && price["Price"].to_i.positive? }
          .minmax_by { |price| price["Price"].to_i }.compact.uniq
        row = row.merge(key => [ { "Fares" => adult } ])
      end
      row
    end

    def zh(value)
      value.is_a?(Hash) ? value["Zh_tw"].to_s : value.to_s
    end
  end
end
