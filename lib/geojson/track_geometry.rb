# frozen_string_literal: true

module Geojson
  # Shared track projection helpers for stations and depot spurs.
  module TrackGeometry
    # Only pull a station onto the centerline when it is already this close (meters).
    STATION_ALIGN_THRESHOLD_M = 25
    # Draw a depot spur when the facility is farther than this from the route (meters).
    DEPOT_EXTENSION_THRESHOLD_M = 50

    module_function

    def nearest_on_line_strings(lon, lat, line_strings)
      best_lon = lon
      best_lat = lat
      best_distance = Float::INFINITY

      line_strings.each do |coordinates|
        coordinates.each_cons(2) do |start, finish|
          projected_lon, projected_lat, distance = project_on_segment(lon, lat, start, finish)
          next unless distance < best_distance

          best_distance = distance
          best_lon = projected_lon
          best_lat = projected_lat
        end
      end

      [ best_lon, best_lat, best_distance ]
    end

    def align_point_to_lines(lon, lat, line_strings, threshold_m: STATION_ALIGN_THRESHOLD_M)
      projected_lon, projected_lat, distance = nearest_on_line_strings(lon, lat, line_strings)

      if distance <= threshold_m
        [ projected_lon, projected_lat ]
      else
        [ lon, lat ]
      end
    end

    # Returns [[track_lon, track_lat], [target_lon, target_lat]] or nil when already on track.
    def spur_coordinates_for_point(lon, lat, line_strings, threshold_m: DEPOT_EXTENSION_THRESHOLD_M)
      track_lon, track_lat, distance = nearest_on_line_strings(lon, lat, line_strings)
      return nil if distance <= threshold_m

      [ [ track_lon, track_lat ], [ lon, lat ] ]
    end

    def project_on_segment(lon, lat, start_coord, end_coord)
      start_lon, start_lat = start_coord
      end_lon, end_lat = end_coord
      delta_lon = end_lon - start_lon
      delta_lat = end_lat - start_lat

      t = if delta_lon.zero? && delta_lat.zero?
        0.0
      else
        raw = ((lon - start_lon) * delta_lon + (lat - start_lat) * delta_lat) /
              (delta_lon * delta_lon + delta_lat * delta_lat)
        [ [ raw, 0.0 ].max, 1.0 ].min
      end

      projected_lon = start_lon + (t * delta_lon)
      projected_lat = start_lat + (t * delta_lat)
      distance = planar_distance_meters(lon, lat, projected_lon, projected_lat)

      [ projected_lon, projected_lat, distance ]
    end

    def planar_distance_meters(lon_a, lat_a, lon_b, lat_b)
      lat_mid_rad = ((lat_a + lat_b) / 2.0) * Math::PI / 180.0
      delta_lat = (lat_b - lat_a) * 111_320.0
      delta_lon = (lon_b - lon_a) * 111_320.0 * Math.cos(lat_mid_rad)

      Math.sqrt((delta_lat * delta_lat) + (delta_lon * delta_lon))
    end

    def route_line_strings_from_geojson(path)
      data = JSON.parse(path.read)
      lines = []

      data.fetch("features", []).each do |feature|
        feature_type = feature.dig("properties", "feature_type")
        next unless %w[route express_route].include?(feature_type)

        geometry = feature["geometry"]
        case geometry["type"]
        when "LineString"
          lines << geometry["coordinates"]
        when "MultiLineString"
          lines.concat(geometry["coordinates"])
        end
      end

      lines
    end
  end
end
