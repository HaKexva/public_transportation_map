# frozen_string_literal: true

module Transit
  # Cumulative kilometers along a route polyline for O(log n) position lookup.
  class TrackChainage
    def self.for_route(route)
      new(route).build
    end

    def initialize(route)
      @route = route
    end

    def build
      line = longest_line
      return nil if line.nil? || line.length < 2

      cum = [ 0.0 ]
      (1...line.length).each do |i|
        cum << (cum.last + haversine_km(line[i - 1], line[i]))
      end

      { line: line, cum: cum, length_km: cum.last }
    end

    def self.point_at(chainage, distance_km)
      return nil unless chainage

      line = chainage[:line]
      cum = chainage[:cum]
      return nil if line.blank? || cum.blank?

      dist = distance_km.to_f.clamp(0.0, cum.last)
      return { lat: line[0][1], lng: line[0][0] } if dist <= 0
      return { lat: line[-1][1], lng: line[-1][0] } if dist >= cum.last

      hi = cum.bsearch_index { |value| value >= dist } || (cum.length - 1)
      lo = [ hi - 1, 0 ].max
      span = cum[hi] - cum[lo]
      t = span.positive? ? ((dist - cum[lo]) / span) : 0.0
      a = line[lo]
      b = line[hi]
      {
        lat: a[1] + ((b[1] - a[1]) * t),
        lng: a[0] + ((b[0] - a[0]) * t)
      }
    end

    def self.nearest_distance(chainage, lng, lat)
      return nil unless chainage

      line = chainage[:line]
      cum = chainage[:cum]
      best_d = nil
      best_dist = Float::INFINITY

      (0...(line.length - 1)).each do |i|
        ax, ay = line[i]
        bx, by = line[i + 1]
        dx = bx - ax
        dy = by - ay
        len2 = (dx * dx) + (dy * dy)
        t = len2.positive? ? (((lng - ax) * dx) + ((lat - ay) * dy)) / len2 : 0.0
        t = t.clamp(0.0, 1.0)
        px = ax + (dx * t)
        py = ay + (dy * t)
        dist = Math.sqrt(((lat - py) * 111.0)**2 + ((lng - px) * 101.0)**2)
        next if dist >= best_dist

        best_dist = dist
        seg_km = cum[i + 1] - cum[i]
        best_d = cum[i] + (seg_km * t)
      end

      best_d
    end

    private

    def longest_line
      path = @route.geojson_path.to_s.delete_prefix("/")
      full = Rails.root.join("public", path)
      return nil unless File.file?(full)

      data = JSON.parse(File.read(full))
      lines = []
      Array(data["features"]).each do |feature|
        props = feature["properties"] || {}
        next unless props["feature_type"] == "route" || props["feature_type"] == "express_route"

        geometry = feature["geometry"] || {}
        if geometry["type"] == "LineString"
          lines << geometry["coordinates"] if geometry["coordinates"].is_a?(Array)
        elsif geometry["type"] == "MultiLineString"
          Array(geometry["coordinates"]).each { |coords| lines << coords if coords.is_a?(Array) }
        end
      end
      lines.max_by { |line| line.is_a?(Array) ? line.length : 0 }
    rescue JSON::ParserError, Errno::ENOENT
      nil
    end

    def haversine_km(a, b)
      lat1 = a[1].to_f * Math::PI / 180.0
      lat2 = b[1].to_f * Math::PI / 180.0
      dlat = lat2 - lat1
      dlng = (b[0].to_f - a[0].to_f) * Math::PI / 180.0
      h = Math.sin(dlat / 2)**2 + (Math.cos(lat1) * Math.cos(lat2) * Math.sin(dlng / 2)**2)
      2 * 6371.0 * Math.asin([ Math.sqrt(h), 1.0 ].min)
    end
  end
end
