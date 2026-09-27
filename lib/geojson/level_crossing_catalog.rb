# frozen_string_literal: true

require "json"
require "net/http"

module Geojson
  # TRA level crossings from OpenStreetMap `railway=level_crossing` nodes,
  # snapped to this app's TRA route geometry. Pass times are estimated on the
  # client from the local timetable.
  class LevelCrossingCatalog
    OUTPUT = Rails.root.join("public/geojson/level_crossings.json")
    OVERPASS_URLS = [
      "https://overpass-api.de/api/interpreter",
      "https://overpass.kumi.systems/api/interpreter"
    ].freeze
    TAIWAN_BBOX = "21.8,119.3,25.4,122.1"
    MAX_SNAP_METERS = 25.0
    GRID_DEGREES = 0.01
    USER_AGENT = "public-transportation-map/1.0 (level crossing catalog)"

    def self.refresh!(output: OUTPUT, route_ids: nil, fetcher: nil)
      new(output: output, route_ids: route_ids, fetcher: fetcher).refresh!
    end

    def initialize(output: OUTPUT, route_ids: nil, fetcher: nil)
      @output = Pathname(output)
      @route_ids = Array(route_ids).map(&:to_s).reject(&:blank?).presence
      @fetcher = fetcher || method(:fetch_osm_crossings)
    end

    def refresh!
      routes = tra_routes
      index = build_segment_index(routes)
      features = @fetcher.call.filter_map { |node| feature_for(node, index) }
      features.sort_by! { |feature| feature["properties"]["id"] }

      payload = {
        "type" => "FeatureCollection",
        "name" => "tra_level_crossings",
        "attribution" => "© OpenStreetMap contributors (ODbL)",
        "features" => features
      }
      @output.dirname.mkpath
      @output.write(JSON.generate(payload))
      features.length
    end

    private

    def tra_routes
      scope = TransitRoute.where(system_id: "tra")
      scope = scope.where(route_id: @route_ids) if @route_ids
      scope.to_a
    end

    # { [cell_x, cell_y] => [ [route, [lng, lat], [lng, lat]], ... ] }
    def build_segment_index(routes)
      index = Hash.new { |hash, key| hash[key] = [] }
      routes.each do |route|
        route_lines(route).each do |line|
          line.each_cons(2) do |a, b|
            cells_for_segment(a, b).each { |cell| index[cell] << [ route, a, b ] }
          end
        end
      end
      index
    end

    def route_lines(route)
      path = Rails.root.join("public", route.geojson_path.to_s.delete_prefix("/"))
      return [] unless File.file?(path)

      data = JSON.parse(File.read(path))
      Array(data["features"]).flat_map do |feature|
        type = feature.dig("properties", "feature_type")
        next [] unless type == "route" || type == "express_route"

        geometry = feature["geometry"] || {}
        case geometry["type"]
        when "LineString" then [ geometry["coordinates"] ]
        when "MultiLineString" then Array(geometry["coordinates"])
        else []
        end
      end.select { |line| line.is_a?(Array) && line.length >= 2 }
    rescue JSON::ParserError
      []
    end

    def cells_for_segment(a, b)
      x0, x1 = [ a[0], b[0] ].minmax.map { |v| (v / GRID_DEGREES).floor }
      y0, y1 = [ a[1], b[1] ].minmax.map { |v| (v / GRID_DEGREES).floor }
      (x0..x1).flat_map { |x| (y0..y1).map { |y| [ x, y ] } }
    end

    def feature_for(node, index)
      lng = node["lon"].to_f
      lat = node["lat"].to_f
      best = nearest_route(index, lng, lat)
      return nil unless best && best[:meters] <= MAX_SNAP_METERS

      route = best[:route]
      tags = node["tags"] || {}
      near = nearest_station_name(route, lat, lng)
      name = tags["name"].presence || tags["name:zh"].presence || (near && "#{near}附近平交道")

      {
        "type" => "Feature",
        "properties" => {
          "id" => "osm:#{node['id']}",
          "name" => name,
          "near_station" => near,
          "route_id" => route.route_id,
          "source" => "osm"
        }.compact,
        "geometry" => { "type" => "Point", "coordinates" => [ lng.round(7), lat.round(7) ] }
      }
    end

    def nearest_route(index, lng, lat)
      cx = (lng / GRID_DEGREES).floor
      cy = (lat / GRID_DEGREES).floor
      best = nil
      (-1..1).each do |dx|
        (-1..1).each do |dy|
          index.fetch([ cx + dx, cy + dy ], []).each do |route, a, b|
            meters = point_segment_meters(lng, lat, a, b)
            best = { route: route, meters: meters } if best.nil? || meters < best[:meters]
          end
        end
      end
      best
    end

    def point_segment_meters(lng, lat, a, b)
      scale_x = 111_320.0 * Math.cos(lat * Math::PI / 180.0)
      scale_y = 110_540.0
      ax = (a[0] - lng) * scale_x
      ay = (a[1] - lat) * scale_y
      bx = (b[0] - lng) * scale_x
      by = (b[1] - lat) * scale_y
      dx = bx - ax
      dy = by - ay
      len2 = (dx * dx) + (dy * dy)
      t = len2.positive? ? (-((ax * dx) + (ay * dy)) / len2).clamp(0.0, 1.0) : 0.0
      Math.hypot(ax + (dx * t), ay + (dy * t))
    end

    def nearest_station_name(route, lat, lng)
      @stations_by_route ||= {}
      stations = @stations_by_route[route.id] ||= route.transit_route_stations.to_a.filter_map do |station|
        coord = Transit::GeojsonStationCoords.lookup(route, station.station_ref)
        [ station.name, coord ] if coord && station.name.present?
      end
      stations.min_by { |_name, coord| ((coord[0] - lat)**2) + ((coord[1] - lng)**2) }&.first
    end

    def fetch_osm_crossings
      query = %([out:json][timeout:120];node["railway"="level_crossing"](#{TAIWAN_BBOX});out;)
      last_error = nil
      OVERPASS_URLS.each do |base_url|
        uri = URI(base_url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = 30
        http.read_timeout = 180
        request = Net::HTTP::Post.new(uri.path, "User-Agent" => USER_AGENT, "Accept" => "application/json")
        request.set_form_data("data" => query)
        response = http.request(request)
        return Array(JSON.parse(response.body)["elements"]) if response.is_a?(Net::HTTPSuccess)

        last_error = "Overpass request failed (#{response.code}) at #{base_url}"
      rescue StandardError => e
        last_error = "#{e.class}: #{e.message} at #{base_url}"
      end
      raise last_error || "Overpass request failed"
    end
  end
end
