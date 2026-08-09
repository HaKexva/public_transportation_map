# frozen_string_literal: true

require "json"

module Transit
  # Reads station coordinates and main-line route polylines from on-disk GeoJSON.
  class GeojsonStationCoords
    class << self
      def lookup(route, station_ref)
        return nil if route.nil? || station_ref.blank?

        index = index_for(route)
        tokens = ref_tokens(station_ref)
        tokens.each do |token|
          coord = index[token]
          return coord if coord
        end

        index.each do |key, coord|
          key_tokens = ref_tokens(key)
          return coord if tokens.any? { |token| key_tokens.include?(token) }
        end

        if route.system_id.to_s == "tra"
          tra = tra_index
          tokens.each do |token|
            coord = tra[token]
            return coord if coord
          end
        end

        nil
      end

      def lookup_name(route, station_ref)
        return nil if route.nil? || station_ref.blank?

        names = name_index_for(route)
        ref_tokens(station_ref).each do |token|
          name = sanitized_station_name(names[token])
          return name if name
        end

        name = sanitized_station_name(names[station_ref.to_s])
        return name if name

        if route.system_id.to_s == "tra"
          tra_names = tra_name_index
          ref_tokens(station_ref).each do |token|
            name = sanitized_station_name(tra_names[token])
            return name if name
          end
        end

        nil
      end

      def interpolate(route, from_ref, to_ref, progress)
        from = lookup(route, from_ref)
        to = lookup(route, to_ref)
        return nil unless from && to

        t = progress.to_f.clamp(0.0, 1.0)
        along = interpolate_along_route(route, from, to, t) || {
          lat: from[0] + ((to[0] - from[0]) * t),
          lng: from[1] + ((to[1] - from[1]) * t)
        }

        {
          lat: along[:lat],
          lng: along[:lng],
          from_lat: from[0],
          from_lng: from[1],
          to_lat: to[0],
          to_lng: to[1]
        }
      end

      def clear_cache!
        @station_indexes = {}
        @tra_index = nil
        @tra_name_index = nil
        @polylines = {}
      end

      private

      def index_for(route)
        station_indexes_for(route)[:coords]
      end

      def name_index_for(route)
        station_indexes_for(route)[:names]
      end

      def station_indexes_for(route)
        @station_indexes ||= {}
        route_id = route.route_id.to_s
        return @station_indexes[route_id] if @station_indexes.key?(route_id)

        @station_indexes[route_id] = build_station_indexes(route)
      end

      def polylines_for(route)
        @polylines ||= {}
        route_id = route.route_id.to_s
        return @polylines[route_id] if @polylines.key?(route_id)

        @polylines[route_id] = build_polylines(route)
      end

      def tra_index
        @tra_index ||= merge_tra_indexes(:coords)
      end

      def tra_name_index
        @tra_name_index ||= merge_tra_indexes(:names)
      end

      def merge_tra_indexes(field)
        merged = {}
        TransitRoute.where(system_id: "tra").find_each do |route|
          station_indexes_for(route)[field].each do |key, value|
            merged[key] ||= value
          end
        end
        merged
      end

      def ref_tokens(ref)
        ref.to_s.split(";").map(&:strip).reject(&:blank?)
      end

      def sanitized_station_name(value)
        name = value.to_s.strip
        return nil if name.blank? || name.include?(";")

        name
      end

      def interpolate_along_route(route, from, to, progress)
        best = nil
        best_score = nil

        polylines_for(route).each do |line|
          from_hit = nearest_on_polyline(line, from[1], from[0])
          to_hit = nearest_on_polyline(line, to[1], to[0])
          next unless from_hit && to_hit
          next if from_hit[:distance] > 250 || to_hit[:distance] > 250

          span = (to_hit[:distance_along] - from_hit[:distance_along]).abs
          next if span < 30

          score = from_hit[:distance] + to_hit[:distance] - (span * 0.001)
          next if best_score && score >= best_score

          best_score = score
          point = point_along_span(line, from_hit[:distance_along], to_hit[:distance_along], progress)
          best = { lat: point[1], lng: point[0] } if point
        end

        best
      end

      def nearest_on_polyline(line, lon, lat)
        best = nil
        along_before = 0.0

        (0...(line.length - 1)).each do |i|
          x1, y1 = line[i]
          x2, y2 = line[i + 1]
          dx = x2 - x1
          dy = y2 - y1
          len2 = (dx * dx) + (dy * dy)
          t = len2.positive? ? (((lon - x1) * dx) + ((lat - y1) * dy)) / len2 : 0.0
          t = t.clamp(0.0, 1.0)
          px = x1 + (dx * t)
          py = y1 + (dy * t)
          # Cheap planar meters near Taiwan (~111km per degree).
          dist = Math.sqrt(((lat - py) * 111_000)**2 + ((lon - px) * 101_000)**2)
          seg_len = Math.sqrt(((y2 - y1) * 111_000)**2 + ((x2 - x1) * 101_000)**2)
          along = along_before + (seg_len * t)

          if best.nil? || dist < best[:distance]
            best = { distance: dist, distance_along: along, index: i + t }
          end

          along_before += seg_len
        end

        best
      end

      def point_along_span(line, from_along, to_along, progress)
        total = 0.0
        (0...(line.length - 1)).each do |i|
          a = line[i]
          b = line[i + 1]
          total += Math.sqrt(((b[1] - a[1]) * 111_000)**2 + ((b[0] - a[0]) * 101_000)**2)
        end

        target = from_along + ((to_along - from_along) * progress.to_f)
        target = target.clamp(0.0, total)

        traveled = 0.0
        (0...(line.length - 1)).each do |i|
          a = line[i]
          b = line[i + 1]
          seg = Math.sqrt(((b[1] - a[1]) * 111_000)**2 + ((b[0] - a[0]) * 101_000)**2)
          if traveled + seg >= target || i == line.length - 2
            ratio = seg.positive? ? ((target - traveled) / seg).clamp(0.0, 1.0) : 0.0
            return [ a[0] + ((b[0] - a[0]) * ratio), a[1] + ((b[1] - a[1]) * ratio) ]
          end
          traveled += seg
        end

        line.last
      end

      def build_station_indexes(route)
        path = absolute_geojson_path(route)
        return { coords: {}, names: {} } unless path && File.file?(path)

        data = JSON.parse(File.read(path))
        coords = {}
        names = {}

        Array(data["features"]).each do |feature|
          props = feature["properties"] || {}
          next unless props["feature_type"] == "station"

          ref = props["ref"].to_s
          geometry = feature.dig("geometry", "coordinates")
          next if ref.blank? || !geometry.is_a?(Array) || geometry.length < 2

          latlng = [ geometry[1].to_f, geometry[0].to_f ]
          name = sanitized_station_name(props["name"])
          ref_tokens(ref).each do |token|
            coords[token] ||= latlng
            names[token] ||= name if name
          end
          coords[ref] ||= latlng
          names[ref] ||= name if name
        end

        { coords: coords, names: names }
      rescue JSON::ParserError, Errno::ENOENT
        { coords: {}, names: {} }
      end

      def build_polylines(route)
        path = absolute_geojson_path(route)
        return [] unless path && File.file?(path)

        data = JSON.parse(File.read(path))
        lines = []

        Array(data["features"]).each do |feature|
          props = feature["properties"] || {}
          next unless props["feature_type"] == "route" || props["feature_type"] == "express_route"

          geometry = feature["geometry"] || {}
          if geometry["type"] == "LineString"
            coords = geometry["coordinates"]
            lines << coords if coords.is_a?(Array) && coords.length >= 2
          elsif geometry["type"] == "MultiLineString"
            Array(geometry["coordinates"]).each do |coords|
              lines << coords if coords.is_a?(Array) && coords.length >= 2
            end
          end
        end

        lines
      rescue JSON::ParserError, Errno::ENOENT
        []
      end

      def absolute_geojson_path(route)
        relative = route.geojson_path.to_s
        return nil if relative.blank?

        relative = relative.delete_prefix("/")
        Rails.root.join("public", relative)
      end
    end
  end
end
