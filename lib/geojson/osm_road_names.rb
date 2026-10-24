# frozen_string_literal: true

module Geojson
  # Names the street a bus stop stands on from the named ways in OsmRoadTiles.
  # A stop near a junction is closest to whichever road the bus runs along, so
  # ways lined up with the bus heading win over a nearer cross street.
  class OsmRoadNames
    SEARCH_METERS = 40.0
    ALIGNED_DEGREES = 35.0
    TILE_CACHE = 64
    BUCKET_DEGREES = 0.001

    def self.default
      OsmRoadTiles.available? ? new : nil
    end

    def initialize(tile_loader: OsmRoadTiles.method(:load_tile))
      @tile_loader = tile_loader
      @tiles = {}
    end

    # `heading` is the bus travel bearing in degrees (0 = north), or nil.
    def road_at(lon, lat, heading = nil)
      candidates = named_segments_near(lon, lat).filter_map do |name, a, b|
        distance = segment_distance(lon, lat, a, b)
        next if distance > SEARCH_METERS

        [ name, distance, heading && axis_difference(heading, bearing(a, b)) ]
      end
      return nil if candidates.empty?

      aligned = candidates.select { |_name, _distance, diff| diff && diff <= ALIGNED_DEGREES }
      (aligned.presence || candidates).min_by { |_name, distance, _diff| distance }.first
    end

    def self.bearing(from, to)
      lat_scale = 111_320.0
      lon_scale = lat_scale * Math.cos(from[1] * Math::PI / 180)
      (Math.atan2((to[0] - from[0]) * lon_scale, (to[1] - from[1]) * lat_scale) * 180 / Math::PI) % 360
    end

    private

    def named_segments_near(lon, lat)
      pad = SEARCH_METERS / 100_000.0
      keys = OsmRoadTiles.tile_keys_for_bbox(lon - pad, lat - pad, lon + pad, lat + pad)
      cells = cells_for_bbox(lon - pad, lat - pad, lon + pad, lat + pad)
      keys.flat_map { |key| buckets = tile(key); cells.flat_map { |cell| buckets[cell] || [] } }.uniq
    end

    def tile(key)
      if @tiles.key?(key)
        @tiles[key] = @tiles.delete(key)
      else
        @tiles.shift if @tiles.size >= TILE_CACHE
        @tiles[key] = bucket_segments(@tile_loader.call(key))
      end
    end

    def bucket_segments(ways)
      buckets = Hash.new { |hash, cell| hash[cell] = [] }
      ways.each do |way|
        name = way["n"]
        next if name.blank?

        way["c"].each_cons(2) do |a, b|
          segment = [ name, a, b ]
          cells_for_bbox([ a[0], b[0] ].min, [ a[1], b[1] ].min, [ a[0], b[0] ].max, [ a[1], b[1] ].max)
            .each { |cell| buckets[cell] << segment }
        end
      end
      buckets.default_proc = nil
      buckets
    end

    def cells_for_bbox(min_lon, min_lat, max_lon, max_lat)
      xs = ((min_lon / BUCKET_DEGREES).floor..(max_lon / BUCKET_DEGREES).floor)
      ys = ((min_lat / BUCKET_DEGREES).floor..(max_lat / BUCKET_DEGREES).floor)
      xs.flat_map { |x| ys.map { |y| [ x, y ] } }
    end

    def segment_distance(lon, lat, a, b)
      lat_scale = 111_320.0
      lon_scale = lat_scale * Math.cos(lat * Math::PI / 180)
      ax = (a[0] - lon) * lon_scale
      ay = (a[1] - lat) * lat_scale
      bx = (b[0] - lon) * lon_scale
      by = (b[1] - lat) * lat_scale
      dx = bx - ax
      dy = by - ay
      length_sq = (dx * dx) + (dy * dy)
      t = length_sq.zero? ? 0.0 : (-((ax * dx) + (ay * dy)) / length_sq).clamp(0.0, 1.0)
      Math.hypot(ax + (t * dx), ay + (t * dy))
    end

    def bearing(a, b)
      self.class.bearing(a, b)
    end

    def axis_difference(first, second)
      diff = (first - second).abs % 180
      [ diff, 180 - diff ].min
    end
  end
end
