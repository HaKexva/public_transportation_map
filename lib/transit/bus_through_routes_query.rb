# frozen_string_literal: true

module Transit
  # Looks up co-serving bus routes for a stop from per-city `_stop_routes.json`.
  class BusThroughRoutesQuery
    Result = Data.define(:routes, :groups, :error) do
      def initialize(routes:, error:, groups: [])
        super
      end
    end

    SIBLING_RADIUS_METERS = 400
    # Hubs spread one name over many kerbs: 臺北車站(忠孝) … 臺北車站(鄭州).
    HUB_RADIUS_METERS = 800
    # Any pole this close is a stop the rider could equally walk to.
    NEARBY_RADIUS_METERS = 150
    MAX_GROUPS = 24
    INTERCITY_SUBDIR = "intercity_bus"

    def initialize(city_id:, station_id: nil, name: nil, lat: nil, lon: nil, platform: nil, bus_root: nil)
      @city_id = city_id.to_s.presence
      @station_id = station_id.to_s.presence
      @platform = platform.to_s.presence
      @name = name.to_s.presence
      @lat = lat.nil? ? nil : Float(lat)
      @lon = lon.nil? ? nil : Float(lon)
      @bus_root = bus_root
    rescue ArgumentError, TypeError
      @lat = nil
      @lon = nil
    end

    def call
      return Result.new(routes: [], error: "missing_city") if @city_id.blank?

      subdir = Geojson::BusLayout.subdir_for(@city_id)
      return Result.new(routes: [], error: "unknown_city") if subdir.blank?

      index = load_index(subdir)
      return Result.new(routes: [], error: "index_missing") unless index

      Result.new(routes: match_routes(index), groups: nearby_groups(subdir, index), error: nil)
    end

    HUB_SUFFIX = /(?:公車站|客運站|轉運站|轉運中心|總站|外站|車站)\z/

    def self.base_name(name)
      name.to_s.sub(/\s*[(（][^()（）]*[)）]\s*\z/, "").tr("台", "臺").strip
    end

    # 新北板橋公車站 / 板橋車站(文化路) / 板橋轉運站 all name the 板橋 hub.
    def self.hub_root(name)
      base = base_name(name)
      root = base.sub(HUB_SUFFIX, "")
      root if root != base && root.length >= 2
    end

    def self.same_hub?(first, second)
      a = hub_root(first)
      b = hub_root(second)
      return false unless a && b

      a.end_with?(b) || b.end_with?(a)
    end

    private

    # Stop groups around the clicked pole: same-name ones (opposite kerbs,
    # separate platforms), same-place ones with another bracketed street, and
    # any pole a few steps away — from city and intercity indexes alike. The
    # clicked one is flagged `current`.
    def nearby_groups(subdir, index)
      return [] if @name.blank?

      current_key = current_group_key(index["groups"] || {})
      origin = index.dig("groups", current_key) || (@lat && @lon && { "lat" => @lat, "lon" => @lon })
      return [] unless origin

      base = self.class.base_name(@name)
      candidates = [ [ subdir, index ], *neighbour_indexes(subdir, origin) ].flat_map do |source, source_index|
        (source_index["groups"] || {}).filter_map do |key, group|
          current = source == subdir && key == current_key
          distance = distance_meters(origin, group)
          next unless current || related_group?(group["name"], base, distance)

          [ source == subdir ? key : "#{source}:#{key}", key, group, distance, current, source_index ]
        end
      end
      return [] if candidates.length < 2

      candidates.sort_by { |_id, _key, _group, distance, current| [ current ? 0 : 1, distance ] }
        .first(MAX_GROUPS)
        .map do |id, key, group, distance, current, source_index|
          {
            id: id,
            name: group["name"],
            platform: group["platform"],
            platform_en: group["platform_en"],
            road: group["road"],
            toward: group["toward"],
            lat: group["lat"],
            lon: group["lon"],
            distance_m: distance.round,
            bearing: current ? nil : bearing_degrees(origin, group).round,
            current: current,
            stop_uids: group["stops"],
            routes: source_index.dig("stations", key) || source_index.dig("clusters", key) || []
          }
        end
    end

    def related_group?(name, base, distance)
      return true if distance <= NEARBY_RADIUS_METERS
      return distance <= SIBLING_RADIUS_METERS if name == @name

      return false if distance > HUB_RADIUS_METERS

      self.class.base_name(name) == base || self.class.same_hub?(name, @name)
    end

    # City stops share kerbs with intercity coaches, so look at both sides.
    def neighbour_indexes(subdir, origin)
      subdirs = if subdir == INTERCITY_SUBDIR
        city_subdirs_covering(origin)
      else
        [ INTERCITY_SUBDIR ]
      end
      subdirs.filter_map { |other| (other_index = load_index(other)) && [ other, other_index ] }
    end

    def city_subdirs_covering(origin)
      path = Geojson::BusStopIndexWriter.bounds_path(bus_root: @bus_root)
      return [] unless path.exist?

      pad = HUB_RADIUS_METERS / 100_000.0
      JSON.parse(path.read).filter_map do |subdir, (min_lon, min_lat, max_lon, max_lat)|
        next if subdir == INTERCITY_SUBDIR
        next unless origin["lon"].to_f.between?(min_lon - pad, max_lon + pad) && origin["lat"].to_f.between?(min_lat - pad, max_lat + pad)

        subdir
      end
    rescue JSON::ParserError
      []
    end

    def current_group_key(groups)
      platform_station = platform_station_id
      return platform_station if platform_station && groups.key?(platform_station)
      return @station_id if @station_id.present? && groups.key?(@station_id)

      key = cluster_key(@name, @lon, @lat)
      platform_cluster = Geojson::BusStopIndexWriter.platform_key(key, @platform)
      return platform_cluster if platform_cluster && groups.key?(platform_cluster)

      key if key && groups.key?(key)
    end

    def platform_station_id
      Geojson::BusStopIndexWriter.platform_key(@station_id, @platform) if @platform
    end

    def distance_meters(from, to)
      lat_scale = 111_320.0
      lon_scale = lat_scale * Math.cos(from["lat"].to_f * Math::PI / 180)
      Math.hypot((to["lat"].to_f - from["lat"].to_f) * lat_scale, (to["lon"].to_f - from["lon"].to_f) * lon_scale)
    end

    def bearing_degrees(from, to)
      lat_scale = 111_320.0
      lon_scale = lat_scale * Math.cos(from["lat"].to_f * Math::PI / 180)
      dx = (to["lon"].to_f - from["lon"].to_f) * lon_scale
      dy = (to["lat"].to_f - from["lat"].to_f) * lat_scale
      (Math.atan2(dx, dy) * 180 / Math::PI) % 360
    end

    # Parsed indexes stay in process memory: they are tens of MB, and decoding
    # one from Rails.cache costs several times a fresh JSON.parse.
    INDEX_CACHE_SIZE = 3
    @index_cache = {}
    @index_cache_lock = Mutex.new

    def self.cached_index(path)
      key = [ path.to_s, path.mtime.to_f ]
      @index_cache_lock.synchronize do
        if @index_cache.key?(key)
          @index_cache[key] = @index_cache.delete(key)
        else
          @index_cache.delete_if { |(cached_path, _mtime), _index| cached_path == key.first }
          @index_cache.shift while @index_cache.size >= INDEX_CACHE_SIZE
          @index_cache[key] = JSON.parse(path.read)
        end
      end
    end

    def load_index(subdir)
      path = Geojson::BusStopIndexWriter.index_path_for(subdir, bus_root: @bus_root)
      return nil unless path.exist?

      self.class.cached_index(path)
    rescue JSON::ParserError
      nil
    end

    def match_routes(index)
      stations = index["stations"] || {}
      platform_station = platform_station_id
      return stations[platform_station] if platform_station && stations[platform_station].is_a?(Array)
      if @station_id.present? && stations[@station_id].is_a?(Array)
        return stations[@station_id]
      end

      return [] if @name.blank? || @lat.nil? || @lon.nil?

      clusters = index["clusters"] || {}
      cluster = cluster_key(@name, @lon, @lat)
      matched = []
      seen = {}

      push = lambda do |routes|
        Array(routes).each do |route|
          id = route["id"]
          next if id.blank? || seen[id]

          seen[id] = true
          matched << route
        end
      end

      push.call(clusters[cluster]) if cluster

      suffix = "|#{@name}"
      clusters.each do |key, routes|
        next if key == cluster || !key.end_with?(suffix)

        key_lat, key_lon, = key.split("|", 3)
        next if (key_lat.to_f - @lat).abs > 0.0006
        next if (key_lon.to_f - @lon).abs > 0.0006

        push.call(routes)
      end

      matched.sort_by { |route| [ route["ref"].to_s, route["id"].to_s ] }
    end

    def cluster_key(name, lon, lat)
      return if name.blank? || lon.nil? || lat.nil?

      format("%.4f|%.4f|%s", lat, lon, name)
    end
  end
end
