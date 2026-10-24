# frozen_string_literal: true

module Geojson
  # Shortest drivable path over OsmRoadTiles, honouring one-way streets.
  class OsmRoadRouter
    SNAP_METERS = 40.0
    BUCKET_DEGREES = 0.001
    REGION_CACHE = 48

    Snap = Struct.new(:point, :from, :to, :t, :distance, :oneway, :cost, keyword_init: true)

    def initialize
      @regions = {}
    end

    # Metres from `point` to the nearest drivable road (Float::INFINITY if none nearby).
    def distance_to_road(point)
      snap(point)&.distance || Float::INFINITY
    end

    # Road path from `from` to `to` as [lon, lat] points, starting and ending at
    # the points snapped onto the network; nil when either end is off the map.
    def route(from, to)
      region = region_for(from, to)
      start = snap(from, region) or return nil
      finish = snap(to, region) or return nil

      direct = same_edge_path(start, finish)
      return direct if direct

      nodes, edges = region[:nodes], region[:edges]
      start_id = -1
      finish_id = -2
      extra = Hash.new { |hash, key| hash[key] = [] }
      if start.oneway >= 0
        extra[start_id] << [ start.to, edge_cost(start.point, nodes[start.to], start.cost) ]
      end
      if start.oneway <= 0
        extra[start_id] << [ start.from, edge_cost(start.point, nodes[start.from], start.cost) ]
      end
      into_finish = {}
      into_finish[finish.from] = edge_cost(nodes[finish.from], finish.point, finish.cost) if finish.oneway >= 0
      into_finish[finish.to] = edge_cost(nodes[finish.to], finish.point, finish.cost) if finish.oneway <= 0

      best = { start_id => 0.0 }
      previous = {}
      heap = MinHeap.new
      heap.push(0.0, start_id)
      until heap.empty?
        cost, node = heap.pop
        next if cost > best.fetch(node, Float::INFINITY)
        break if node == finish_id

        neighbours = node.negative? ? extra[node] : edges[node]
        neighbours.each do |target, weight|
          relax(best, previous, heap, node, target, cost + weight)
        end
        if (into = into_finish[node])
          relax(best, previous, heap, node, finish_id, cost + into)
        end
      end
      return nil unless previous.key?(finish_id)

      path = []
      node = previous[finish_id]
      while node && node != start_id
        path.unshift(nodes[node])
        node = previous[node]
      end
      [ start.point ] + path + [ finish.point ]
    end

    def snap(point, region = region_for(point, point))
      lon, lat = point
      bx = (lon / BUCKET_DEGREES).floor
      by = (lat / BUCKET_DEGREES).floor
      best = nil
      (-1..1).each do |dx|
        (-1..1).each do |dy|
          Array(region[:buckets][[ bx + dx, by + dy ]]).each do |segment|
            a = region[:nodes][segment[0]]
            b = region[:nodes][segment[1]]
            projected, t = project(point, a, b)
            distance = meters_between(point, projected)
            next if distance > SNAP_METERS
            next if best && distance >= best.distance

            best = Snap.new(point: projected, from: segment[0], to: segment[1], t:, distance:, oneway: segment[2], cost: segment[3])
          end
        end
      end
      best
    end

    private

    def relax(best, previous, heap, node, target, cost)
      return if cost >= best.fetch(target, Float::INFINITY)

      best[target] = cost
      previous[target] = node
      heap.push(cost, target)
    end

    # Both ends on one road segment, in a drivable order.
    def same_edge_path(start, finish)
      same = start.from == finish.from && start.to == finish.to
      return nil unless same

      forward = finish.t >= start.t
      return nil if forward && start.oneway.negative?
      return nil if !forward && start.oneway.positive?

      [ start.point, finish.point ]
    end

    def edge_cost(a, b, multiplier)
      meters_between(a, b) * multiplier
    end

    # Graph over the 3×3 tiles around the request (cached per centre tile).
    def region_for(from, to)
      lon = (from[0] + to[0]) / 2.0
      lat = (from[1] + to[1]) / 2.0
      key = Geojson::OsmRoadTiles.tile_key(lon, lat)
      if (region = @regions.delete(key))
        @regions[key] = region
        return region
      end

      @regions.shift if @regions.length >= REGION_CACHE
      @regions[key] = build_region(lon, lat)
    end

    def build_region(lon, lat)
      pad = Geojson::OsmRoadTiles::TILE_DEGREES
      keys = Geojson::OsmRoadTiles.tile_keys_for_bbox(lon - pad, lat - pad, lon + pad, lat + pad)
      ids = {}
      nodes = []
      edges = Hash.new { |hash, key| hash[key] = [] }
      buckets = Hash.new { |hash, key| hash[key] = [] }
      seen = {}

      keys.each do |tile|
        Geojson::OsmRoadTiles.load_tile(tile).each do |way|
          coords = way["c"]
          signature = [ coords.first, coords.last, coords.length ]
          next if seen[signature]

          seen[signature] = true
          oneway = way["o"].to_i
          multiplier = way["k"].to_f
          way_ids = coords.map do |coord|
            ids[coord] ||= begin
              nodes << coord
              nodes.length - 1
            end
          end
          way_ids.each_cons(2) do |a, b|
            next if a == b

            weight = meters_between(nodes[a], nodes[b]) * multiplier
            edges[a] << [ b, weight ] if oneway >= 0
            edges[b] << [ a, weight ] if oneway <= 0
            segment = [ a, b, oneway, multiplier ]
            bucket_keys(nodes[a], nodes[b]).each { |bucket| buckets[bucket] << segment }
          end
        end
      end

      { nodes:, edges:, buckets: }
    end

    def bucket_keys(a, b)
      xs = ([ a[0], b[0] ].min / BUCKET_DEGREES).floor..([ a[0], b[0] ].max / BUCKET_DEGREES).floor
      ys = ([ a[1], b[1] ].min / BUCKET_DEGREES).floor..([ a[1], b[1] ].max / BUCKET_DEGREES).floor
      xs.flat_map { |x| ys.map { |y| [ x, y ] } }
    end

    def project(point, a, b)
      kx = 111_320 * Math.cos(point[1] * Math::PI / 180.0)
      ax = (a[0] - point[0]) * kx
      ay = (a[1] - point[1]) * 110_540
      bx = (b[0] - point[0]) * kx
      by = (b[1] - point[1]) * 110_540
      dx = bx - ax
      dy = by - ay
      length_sq = (dx * dx) + (dy * dy)
      t = length_sq.zero? ? 0.0 : (-(ax * dx) - (ay * dy)) / length_sq
      t = t.clamp(0.0, 1.0)
      [ [ a[0] + ((b[0] - a[0]) * t), a[1] + ((b[1] - a[1]) * t) ], t ]
    end

    def meters_between(left, right)
      dlon = (right[0] - left[0]) * 111_320 * Math.cos(left[1] * Math::PI / 180.0)
      dlat = (right[1] - left[1]) * 110_540
      Math.hypot(dlon, dlat)
    end

    class MinHeap
      def initialize
        @items = []
      end

      def empty?
        @items.empty?
      end

      def push(priority, value)
        @items << [ priority, value ]
        index = @items.length - 1
        while index.positive?
          parent = (index - 1) / 2
          break if @items[parent][0] <= @items[index][0]

          @items[parent], @items[index] = @items[index], @items[parent]
          index = parent
        end
      end

      def pop
        top = @items.first
        last = @items.pop
        unless @items.empty?
          @items[0] = last
          index = 0
          loop do
            left = (index * 2) + 1
            right = left + 1
            smallest = index
            smallest = left if left < @items.length && @items[left][0] < @items[smallest][0]
            smallest = right if right < @items.length && @items[right][0] < @items[smallest][0]
            break if smallest == index

            @items[smallest], @items[index] = @items[index], @items[smallest]
            index = smallest
          end
        end
        top
      end
    end
  end
end
