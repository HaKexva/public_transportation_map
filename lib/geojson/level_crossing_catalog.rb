# frozen_string_literal: true

require "json"

module Geojson
  # Approximate TRA level crossings at mid-corridor points between consecutive
  # passenger stations. Positions come from this app's GeoJSON, not third-party dumps.
  class LevelCrossingCatalog
    OUTPUT = Rails.root.join("public/geojson/level_crossings.json")

    def self.refresh!(output: OUTPUT)
      new(output: output).refresh!
    end

    def initialize(output: OUTPUT)
      @output = output
    end

    def refresh!
      features = []
      TransitRoute.where(system_id: "tra").find_each do |route|
        chainage = Transit::TrackChainage.for_route(route)
        next unless chainage

        stations = route.transit_route_stations.where(direction: %w[both outbound]).ordered.to_a
        stations = route.transit_route_stations.ordered.to_a if stations.length < 3

        stations.each_cons(2) do |from, to|
          from_coord = Transit::GeojsonStationCoords.lookup(route, from.station_ref)
          to_coord = Transit::GeojsonStationCoords.lookup(route, to.station_ref)
          next unless from_coord && to_coord

          d0 = Transit::TrackChainage.nearest_distance(chainage, from_coord[1], from_coord[0])
          d1 = Transit::TrackChainage.nearest_distance(chainage, to_coord[1], to_coord[0])
          next unless d0 && d1

          gap = (d1 - d0).abs
          next if gap < 0.35 || gap > 3.2

          mid = Transit::TrackChainage.point_at(chainage, (d0 + d1) / 2.0)
          next unless mid

          features << {
            "type" => "Feature",
            "properties" => {
              "id" => "#{route.route_id}:#{from.station_ref}:#{to.station_ref}",
              "name" => "#{from.name}–#{to.name}",
              "route_id" => route.route_id,
              "from_ref" => from.station_ref,
              "to_ref" => to.station_ref,
              "d" => ((d0 + d1) / 2.0).round(4),
              "estimate" => true
            },
            "geometry" => {
              "type" => "Point",
              "coordinates" => [ mid[:lng], mid[:lat] ]
            }
          }
        end
      end

      payload = {
        "type" => "FeatureCollection",
        "name" => "tra_level_crossings_estimate",
        "features" => features
      }
      @output = Pathname(@output)
      @output.dirname.mkpath
      @output.write(JSON.pretty_generate(payload))
      features.length
    end
  end
end
