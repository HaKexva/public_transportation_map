# frozen_string_literal: true

module Transit
  module Itinerary
    module Geometry
      EARTH_M = 6_371_000.0
      WALK_METERS_PER_MIN = 80.0
      WALK_FACTOR = 1.3
      RIDE_FACTOR = 1.25
      ACCESS_METERS = 800
      TRANSFER_METERS = 400
      SAME_PLACE_METERS = 30
      CELL_METERS = 200.0
      CELL_DEG = CELL_METERS / 111_320.0
      RIDE_METERS_PER_MIN = {
        "bus" => 300,
        "metro" => 530,
        "rail" => 800,
        "hsr" => 2500,
        "ferry" => 350,
        "flight" => 8_000
      }.freeze

      module_function

      def meters(lat1, lon1, lat2, lon2)
        phi1 = lat1.to_f * Math::PI / 180
        phi2 = lat2.to_f * Math::PI / 180
        dphi = (lat2.to_f - lat1.to_f) * Math::PI / 180
        dlambda = (lon2.to_f - lon1.to_f) * Math::PI / 180
        a = Math.sin(dphi / 2)**2 + Math.cos(phi1) * Math.cos(phi2) * Math.sin(dlambda / 2)**2
        2 * EARTH_M * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
      end

      def walk_minutes(distance_m)
        return 0 if distance_m < SAME_PLACE_METERS

        [ (distance_m * WALK_FACTOR / WALK_METERS_PER_MIN).ceil, 1 ].max
      end

      def ride_minutes(lat1, lon1, lat2, lon2, mode)
        distance_m = meters(lat1, lon1, lat2, lon2) * RIDE_FACTOR
        speed = RIDE_METERS_PER_MIN.fetch(mode.to_s, 300)
        [ (distance_m / speed).ceil, 1 ].max
      end

      def cell_index(lat, lon)
        [ (lat.to_f / CELL_DEG).floor, (lon.to_f / CELL_DEG).floor ]
      end

      def normalize(text)
        BusStopSearch.normalize(text)
      end

      def clip_geojson(path, from_lat, from_lon, to_lat, to_lon)
        return nil if path.blank?

        file = path.to_s.start_with?("/") ? Rails.root.join("public#{path}") : Rails.root.join(path)
        return nil unless file.exist?

        best = nil
        best_score = nil
        lines_for(file).each do |line|
          from_hit = nearest_vertex(line, from_lon, from_lat)
          to_hit = nearest_vertex(line, to_lon, to_lat)
          next if from_hit.nil? || to_hit.nil?

          score = from_hit[:distance] + to_hit[:distance]
          next if best_score && score >= best_score

          left, right = [ from_hit[:index], to_hit[:index] ].minmax
          slice = line[left..right]
          next if slice.nil? || slice.length < 2

          slice = slice.reverse if from_hit[:index] > to_hit[:index]
          best_score = score
          best = slice
        end
        return nil if best.nil?

        step = [ (best.length / 250.0).ceil, 1 ].max
        simplified = best.each_with_index.filter_map { |point, index| [ point[1], point[0] ] if (index % step).zero? || index == best.length - 1 }
        simplified.length >= 2 ? simplified : nil
      end

      def lines_for(file)
        @lines ||= {}
        stamp = file.mtime.to_f
        cached = @lines[file.to_s]
        return cached[:lines] if cached && cached[:stamp] == stamp

        data = JSON.parse(File.read(file))
        lines = []
        Array(data["features"]).each do |feature|
          geometry = feature["geometry"] || {}
          if geometry["type"] == "LineString"
            lines << geometry["coordinates"] if geometry["coordinates"].is_a?(Array)
          elsif geometry["type"] == "MultiLineString"
            Array(geometry["coordinates"]).each { |line| lines << line if line.is_a?(Array) }
          end
        end
        @lines[file.to_s] = { stamp:, lines: }
        lines
      rescue JSON::ParserError, Errno::ENOENT
        []
      end

      def nearest_vertex(line, lon, lat)
        best = nil
        line.each_with_index do |point, index|
          next unless point.is_a?(Array) && point.length >= 2

          distance = meters(lat, lon, point[1], point[0])
          best = { index:, distance: } if best.nil? || distance < best[:distance]
        end
        best
      end
    end
  end
end
