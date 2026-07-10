# frozen_string_literal: true

module Transit
  class CatalogSync
    Result = Data.define(:routes, :stations)

    def self.sync!
      new.sync!
    end

    def sync!
      route_count = 0
      station_count = 0

      RouteCatalog.manifest.each do |system_id, routes|
        next unless routes.is_a?(Array)

        routes.each do |entry|
          route = upsert_route!(system_id, entry)
          route_count += 1
          station_count += sync_stations!(route, entry)
        end
      end

      Result.new(routes: route_count, stations: station_count)
    end

    private

    def upsert_route!(system_id, entry)
      TransitRoute.find_or_initialize_by(system_id: system_id, route_id: entry.fetch("id")).tap do |route|
        route.name = entry.fetch("name")
        route.name_en = entry["name_en"]
        route.line_ref = entry.fetch("ref")
        route.color = entry["color"]
        route.branch_of_route_id = entry["branch_of"]
        route.geojson_path = entry["file"]
        route.save!
      end
    end

    def sync_stations!(route, entry)
      path = geojson_path(entry)
      return 0 unless path.exist?

      stations = extract_stations(route, JSON.parse(path.read))
      return 0 if stations.empty?

      TransitRouteStation.where(transit_route: route, direction: TransitRoute::DIRECTION_BOTH).delete_all

      stations.each_with_index do |station, index|
        TransitRouteStation.create!(
          transit_route: route,
          station_ref: station.fetch(:ref),
          name: station.fetch(:name),
          name_en: station[:name_en],
          stop_sequence: index + 1,
          direction: TransitRoute::DIRECTION_BOTH
        )
      end

      stations.length
    end

    def extract_stations(route, geojson)
      seen_refs = {}

      (geojson.fetch("features", [])).filter_map do |feature|
        next unless StationRef.passenger_station?(feature)

        ref = feature.dig("properties", "ref").to_s
        next unless StationRef.matches_route?(
          ref,
          line_ref: route.line_ref,
          route_id: route.route_id,
          system_id: route.system_id
        )
        next if seen_refs.key?(ref)

        seen_refs[ref] = true

        {
          ref: ref,
          name: feature.dig("properties", "name").to_s,
          name_en: feature.dig("properties", "name_en")
        }
      end
    end

    def geojson_path(entry)
      relative = entry.fetch("file").delete_prefix("/")
      Rails.public_path.join(relative)
    end
  end
end
