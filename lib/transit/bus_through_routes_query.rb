# frozen_string_literal: true

module Transit
  # Looks up co-serving bus routes for a stop from per-city `_stop_routes.json`.
  class BusThroughRoutesQuery
    Result = Data.define(:routes, :error)

    def initialize(city_id:, station_id: nil, name: nil, lat: nil, lon: nil, bus_root: nil)
      @city_id = city_id.to_s.presence
      @station_id = station_id.to_s.presence
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

      Result.new(routes: match_routes(index), error: nil)
    end

    private

    def load_index(subdir)
      path = Geojson::BusStopIndexWriter.index_path_for(subdir, bus_root: @bus_root)
      return nil unless path.exist?

      Rails.cache.fetch([ "bus_stop_index/v1", subdir, path.to_s, path.mtime.to_i ], expires_in: 6.hours) do
        JSON.parse(path.read)
      end
    rescue JSON::ParserError
      nil
    end

    def match_routes(index)
      stations = index["stations"] || {}
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
