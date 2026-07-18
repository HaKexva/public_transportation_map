# frozen_string_literal: true

require "json"

module Geojson
  # Rebuild depot_spur features on existing route GeoJSON without refetching OSM track.
  module DepotSpurRefresher
    def self.refresh_all!
      updated = []

      MetroDepotCatalog::DEPOTS.each do |depot|
        route_id = MetroDepotCatalog.depot_track_route_id(depot)
        path = MetroDepotCatalog.send(:route_geojson_path, route_id)
        next unless path&.exist?

        refresh_file!(path, route_id)
        updated << route_id unless updated.include?(route_id)
      end

      updated
    end

    def self.refresh_file!(path, route_id)
      data = JSON.parse(path.read)
      line = line_for_route(route_id)
      return unless line

      features = data.fetch("features", []).reject do |feature|
        feature.dig("properties", "feature_type") == "depot_spur"
      end

      line_strings = TrackGeometry.route_line_strings_from_geojson(path)
      MetroDepotCatalog.depots_for_route(route_id).each do |depot|
        next if DepotSpurCatalog.omit_spur?(depot[:id])

        facility = MetroDepotCatalog.primary_facility_coordinates(depot)
        spur_line_strings = DepotSpurCatalog.line_strings_for_depot(depot[:id])
        junction_hint = DepotSpurCatalog.junction_hint_for(depot[:id])
        coordinates = TrackGeometry.depot_link_coordinates_for_point(
          facility[:lon],
          facility[:lat],
          line_strings,
          spur_line_strings: spur_line_strings,
          junction_reference_lon: junction_hint&.dig(:lon),
          junction_reference_lat: junction_hint&.dig(:lat)
        )
        next unless coordinates

        features << spur_feature(line, depot, coordinates)
      end

      data["features"] = features
      File.write(path, JSON.pretty_generate(data))
    end

    def self.spur_feature(line, depot, coordinates)
      {
        type: "Feature",
        properties: {
          feature_type: "depot_spur",
          ref: line.ref,
          name: "#{depot[:name]}支線",
          color: line.color,
          depot_id: depot[:id]
        },
        geometry: {
          type: "LineString",
          coordinates: coordinates
        }
      }
    end

    def self.line_for_route(route_id)
      catalogs = [
        TaipeiMetroCatalog::LINES,
        NewTaipeiMetroCatalog::LINES,
        TaoyuanMetroCatalog::LINES,
        TaichungMetroCatalog::LINES,
        KaohsiungMetroCatalog::LINES,
        HsrCatalog::LINES,
        TraCatalog::LINES,
        SugarRailwayCatalog::LINES,
        OtherTransitCatalog::LINES
      ]

      catalogs.lazy.flat_map(&:itself).find { |line| line.slug == route_id }
    end

    private_class_method :spur_feature, :line_for_route
  end
end
