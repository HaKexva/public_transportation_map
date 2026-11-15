# frozen_string_literal: true

require "net/http"
require "zlib"

module Transit
  # Which buses actually run each route: the registered fleet (bus_vehicles)
  # joined with buses seen on the route in the live feeds
  # (bus_route_vehicle_sightings). 大臺北 publishes both feeds without a key;
  # other cities come from TDX.
  #
  #   bin/rails transit:refresh_bus_vehicles      # daily
  #   bin/rails transit:collect_bus_sightings     # every 10 minutes
  module BusFleet
    BLOB_BASE = "https://tcgbusfs.blob.core.windows.net"
    BLOB_FEEDS = { "Taipei" => "blobbus", "NewTaipei" => "ntpcbus" }.freeze
    SUMMARY_WINDOW = 30.days
    RETENTION = 90.days
    MIN_SHARE = 0.05
    MAX_ROWS = 5

    VEHICLE_CLASSES = { 1 => "large", 2 => "medium", 3 => "small" }.freeze

    module_function

    # --- registered vehicles -------------------------------------------------

    def refresh_vehicles!(client: TdxClient.new(ignore_breaker: true))
      stored = 0
      failed = []
      BLOB_FEEDS.each do |city_id, feed|
        stored += store_vehicles!(city_id, parse_vehicle_xml(blob(feed, "GetBusVehicleList.gz")))
      rescue StandardError => error
        Rails.logger.warn("[BusFleet] #{city_id} vehicles: #{error.message}")
        failed << city_id
      end
      if client.configured?
        tdx_cities.each do |city|
          stored += store_vehicles!(city.id, client.fetch_all(tdx_path("Vehicle", city)))
        rescue TdxClient::Error => error
          Rails.logger.warn("[BusFleet] #{city.id} vehicles: #{error.message}")
          failed << city.id
        end
      end
      BusRouteVehicleSighting.where(last_seen_at: ...RETENTION.ago).delete_all
      { vehicles: stored, failed: }
    end

    def store_vehicles!(city_id, rows, fetched_at: Time.current)
      records = rows.filter_map do |row|
        plate = row["PlateNumb"].to_s.strip
        next if plate.empty? || plate == "-1"

        {
          plate:, city_id:, operator_id: row["OperatorID"].to_s.presence,
          vehicle_class: row["VehicleClass"].presence&.to_i, vehicle_type: row["VehicleType"].presence&.to_i,
          low_floor: flag?(row["IsLowFloor"]), electric: flag?(row["IsElectric"]), hybrid: flag?(row["IsHybrid"]),
          ramp: flag?(row["HasLiftOrRamp"]), fetched_at:, created_at: fetched_at, updated_at: fetched_at
        }
      end.uniq { |record| record[:plate] }
      records.each_slice(1_000) do |slice|
        BusVehicle.upsert_all(slice, unique_by: :plate, update_only: %i[city_id operator_id vehicle_class vehicle_type low_floor electric hybrid ramp fetched_at])
      end
      records.size
    end

    def parse_vehicle_xml(xml)
      doc = Nokogiri::XML(xml)
      doc.remove_namespaces!
      doc.xpath("//Vehicle").map { |node| node.element_children.to_h { |child| [ child.name, child.text ] } }
    end

    # --- live sightings ------------------------------------------------------

    # tdx: false polls only the keyless 大臺北 feeds; true also asks TDX for the
    # other cities (one request per city).
    def collect_sightings!(tdx: false, client: TdxClient.new(ignore_breaker: true), seen_at: Time.current)
      recorded = 0
      failed = []
      greater_taipei = route_index(BLOB_FEEDS.keys)
      BLOB_FEEDS.each do |city_id, feed|
        rows = Array(JSON.parse(blob(feed, "GetBusData.gz"))["BusInfo"]).map { |bus| [ bus["RouteID"], bus["BusID"] ] }
        recorded += record_sightings!(greater_taipei, rows, seen_at:)
      rescue StandardError => error
        Rails.logger.warn("[BusFleet] #{city_id} sightings: #{error.message}")
        failed << city_id
      end
      if tdx && client.configured? && !TdxClient.breaker_open?
        tdx_cities.each do |city|
          rows = client.fetch_all(tdx_path("RealTimeByFrequency", city), query: { "$select" => "PlateNumb,SubRouteID" })
            .map { |bus| [ bus["SubRouteID"], bus["PlateNumb"] ] }
          recorded += record_sightings!(route_index([ city.id ]), rows, seen_at:)
        rescue TdxClient::Error => error
          Rails.logger.warn("[BusFleet] #{city.id} sightings: #{error.message}")
          failed << city.id
        end
      end
      { sightings: recorded, failed: }
    end

    # rows: [[TDX SubRouteID, plate], ...]
    def record_sightings!(index, rows, seen_at: Time.current)
      records = rows.filter_map do |sub_route_id, plate|
        route_id = index[sub_route_id.to_s]
        plate = plate.to_s.strip
        next if route_id.nil? || plate.empty? || plate == "-1"

        { route_id:, plate:, sightings: 1, first_seen_at: seen_at, last_seen_at: seen_at }
      end.uniq { |record| record.values_at(:route_id, :plate) }
      return 0 if records.empty?

      BusRouteVehicleSighting.upsert_all(
        records, unique_by: %i[route_id plate],
        on_duplicate: Arel.sql("sightings = bus_route_vehicle_sightings.sightings + 1, last_seen_at = EXCLUDED.last_seen_at")
      )
      records.size
    end

    # TDX SubRouteID / RouteID (both used as live-feed route ids) => app route id,
    # via the stored TDX Route rows and the app routes' refs.
    def route_index(city_ids)
      index = {}
      Array(city_ids).each do |city_id|
        by_ref = app_routes_by_ref(city_id)
        next if by_ref.empty?

        BusRouteTimetable.where(city_id:).select(:id, :route_name, :routes).find_each do |row|
          target = by_ref[row.route_name]
          Array(row.routes).each do |route|
            index[route["RouteID"].to_s] ||= target if target
            Array(route["SubRoutes"]).each do |sub|
              sub_target = by_ref[sub.dig("SubRouteName", "Zh_tw").to_s] || target
              index[sub["SubRouteID"].to_s] ||= sub_target if sub_target
            end
          end
        end
      end
      index
    end

    def app_routes_by_ref(city_id)
      routes = Array(RouteCatalog.manifest["bus"]).select { |route| route["city_id"] == city_id }.sort_by { |route| route["id"].length }
      by_ref = {}
      routes.each { |route| by_ref[route["ref"].to_s] ||= route["id"] }
      routes.each { |route| Array(route["merged_refs"]).each { |ref| by_ref[ref.to_s] ||= route["id"] } }
      if Geojson::BusCatalog.find(city_id)&.kind == :intercity
        routes.each { |route| by_ref[route["ref"].to_s.sub(/[A-J]\z/i, "")] ||= route["id"] }
      end
      by_ref.delete("")
      by_ref
    end

    # --- route summary -------------------------------------------------------

    # Common vehicle types and models on a route, weighted by how often each
    # bus was seen there (≈ share of trips). nil until a bus has been seen.
    def summary(route_id, since: SUMMARY_WINDOW.ago)
      rows = BusRouteVehicleSighting.where(route_id:, last_seen_at: since..).pluck(:plate, :sightings)
      return nil if rows.empty?

      vehicles = BusVehicle.where(plate: rows.map(&:first)).index_by(&:plate)
      total = rows.sum(&:last).to_f
      types = Hash.new { |hash, key| hash[key] = [ 0, 0 ] }
      models = Hash.new { |hash, key| hash[key] = [ 0, 0 ] }
      rows.each do |plate, seen|
        vehicle = vehicles[plate]
        if (kind = vehicle_kind(vehicle))
          types[kind][0] += 1
          types[kind][1] += seen
        end
        if (model = BusVehicleModels.lookup(plate, vehicle&.operator_id, vehicle&.city_id))
          models[model][0] += 1
          models[model][1] += seen
        end
      end

      {
        vehicle_count: rows.size,
        types: common(types, total) { |kind, count, share| kind.merge(count:, share:) },
        models: common(models, total) { |name, count, share| { name:, count:, share: } }
      }
    end

    def vehicle_kind(vehicle)
      return nil unless vehicle

      {
        vehicle_class: VEHICLE_CLASSES[vehicle.vehicle_class],
        power: if vehicle.electric then "electric" elsif vehicle.hybrid then "hybrid" end,
        low_floor: (true if vehicle.low_floor)
      }.compact.presence
    end

    def common(tally, total)
      tally.sort_by { |_key, (_count, seen)| -seen }
        .select { |_key, (_count, seen)| seen / total >= MIN_SHARE }
        .first(MAX_ROWS)
        .map { |key, (count, seen)| yield(key, count, (seen * 100 / total).round) }
    end

    # --- helpers -------------------------------------------------------------

    def tdx_cities
      Geojson::BusCatalog.cities.reject { |city| BLOB_FEEDS.key?(city.id) }
    end

    def tdx_path(dataset, city)
      city.kind == :intercity ? "v2/Bus/#{dataset}/InterCity" : "v2/Bus/#{dataset}/City/#{city.tdx_city}"
    end

    def blob(feed, file)
      response = Net::HTTP.get_response(URI("#{BLOB_BASE}/#{feed}/#{file}"))
      raise "#{feed}/#{file} HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      body = response.body
      body = Zlib.gunzip(body) if body.byteslice(0, 2)&.bytes == [ 0x1f, 0x8b ]
      body.force_encoding(Encoding::UTF_8).delete_prefix("\uFEFF")
    end

    def flag?(value)
      value == true || value.to_s == "1" || value.to_s.casecmp?("true")
    end
  end
end
