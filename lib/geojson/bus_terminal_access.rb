# frozen_string_literal: true

module Geojson
  # Some termini are off-street depots: the TDX stop pole (and Shape) stops on
  # the street while buses actually turn in and lay over inside. Each entry is
  # the access path from the street junction to the layover point (OSM roads).
  module BusTerminalAccess
    PATHS = {
      # 欣欣客運華江站: 長順街 → 華江疏散門 → 堤外道路 into the riverside depot.
      "華江站" => [
        [ 121.4888717, 25.0323634 ],
        [ 121.4886935, 25.0324115 ],
        [ 121.4885685, 25.0324452 ],
        [ 121.4885025, 25.0324630 ],
        [ 121.4883507, 25.0319421 ]
      ]
    }.freeze
    JUNCTION_RADIUS_METERS = 40.0
    MAX_STOP_GAP_METERS = 120.0

    module_function

    def process_collection!(data)
      return false unless data.is_a?(Hash)

      features = Array(data["features"])
      stations = features.select { |feature| feature.dig("properties", "feature_type") == "station" }
      stations_by_direction = stations.group_by { |station| station.dig("properties", "direction").to_s }
      changed = false

      features.each do |feature|
        next unless feature.dig("properties", "feature_type") == "route"
        next unless feature.dig("geometry", "type") == "LineString"

        stops = stations_by_direction.fetch(feature.dig("properties", "direction").to_s, [])
        next if stops.empty?

        line = feature.dig("geometry", "coordinates")
        extended = line
        if (path = path_for(stops.last, extended.last))
          extended = arrive(extended, path)
          changed |= move_station!(stops.last, path.last)
        end
        if (path = path_for(stops.first, extended.first))
          extended = arrive(extended.reverse, path).reverse
          changed |= move_station!(stops.first, path.last)
        end
        next if extended == line

        feature["geometry"]["coordinates"] = extended
        changed = true
      end

      changed
    end

    def path_for(station, line_end)
      path = PATHS[station.dig("properties", "name")]
      return nil unless path && line_end

      coordinates = station.dig("geometry", "coordinates")
      return nil if meters_between(line_end, path.last) < 1.0
      return nil if meters_between(coordinates, path.first) > MAX_STOP_GAP_METERS &&
        meters_between(coordinates, path.last) > 1.0
      return nil if meters_between(line_end, path.first) > MAX_STOP_GAP_METERS

      path
    end

    # Cut the line where it last reaches the street junction and follow the
    # access path in, dropping the curbside stub past the junction.
    def arrive(line, path)
      junction = path.first
      start = line.length
      start -= 1 while start.positive? && meters_between(line[start - 1], junction) <= JUNCTION_RADIUS_METERS
      head = start < line.length ? line[0..start] : line
      head = head[0...-1] while head.length > 1 && meters_between(head.last, junction) < 1.0
      head + path
    end

    def move_station!(station, point)
      return false if station.dig("geometry", "coordinates") == point

      station["geometry"]["coordinates"] = point.dup
      true
    end

    def meters_between(left, right)
      Geojson::BusLoopCloser.meters_between(left, right)
    end
  end
end
