# frozen_string_literal: true

require "json"

module Geojson
  # Metro maintenance depots (機廠). Catalog lon/lat are approximate hints;
  # write_json! projects each depot onto the nearest linked route track.
  module MetroDepotCatalog
    DEPOTS = [
      { id: "beitou_depot", name: "北投機廠", routes: %w[tamsui_xinyi], lon: 121.483955, lat: 25.1357899, grade: "五級" },
      { id: "xindian_depot", name: "新店機廠", routes: %w[songshan_xindian xiaobitan_branch], lon: 121.5308, lat: 24.9715, grade: "三級" },
      { id: "nangang_depot", name: "南港機廠", routes: %w[bannan], lon: 121.6075, lat: 25.0512, grade: "三級" },
      { id: "tucheng_depot", name: "土城機廠", routes: %w[bannan], lon: 121.4483, lat: 24.9910, grade: "四級" },
      { id: "zhonghe_depot", name: "中和機廠", routes: %w[zhonghe_xinlu], lon: 121.5056, lat: 24.9958, grade: "一級" },
      { id: "xinzhuang_depot", name: "新莊機廠", routes: %w[zhonghe_xinlu], lon: 121.410, lat: 25.0215, grade: "三級" },
      { id: "luzhou_depot", name: "蘆洲機廠", routes: %w[zhonghe_xinlu], lon: 121.4670, lat: 25.0900, grade: "四級" },
      { id: "muzha_depot", name: "木柵機廠", routes: %w[wenhu_line], lon: 121.5844, lat: 25.0015, grade: "中運量" },
      { id: "neihu_depot", name: "內湖機廠", routes: %w[wenhu_line], lon: 121.6180, lat: 25.0554, grade: "中運量" },
      { id: "qingpu_depot", name: "青埔機廠", routes: %w[airport_mrt], lon: 121.208, lat: 25.0086, grade: "主機廠" },
      { id: "shisizhang_depot", name: "十四張機廠", routes: %w[circular ankeng_lrt], lon: 121.5276, lat: 24.9845, grade: "輕軌" },
      { id: "ankeng_depot", name: "安坑機廠", routes: %w[ankeng_lrt], lon: 121.4860, lat: 24.9450, grade: "輕軌" },
      { id: "danhai_depot", name: "淡海車廠", routes: %w[danhai_lrt], lon: 121.434621, lat: 25.2009501, grade: "輕軌" },
      { id: "kaohsiung_north_depot", name: "北機廠", routes: %w[red_line], lon: 120.2985, lat: 22.7885, grade: "三級" },
      { id: "kaohsiung_south_depot", name: "南機廠", routes: %w[red_line], lon: 120.3288, lat: 22.5785, grade: "三級" },
      { id: "kaohsiung_daliao_depot", name: "大寮機廠", routes: %w[orange_line], lon: 120.392, lat: 22.624, grade: "主機廠" },
      { id: "kaohsiung_circular_depot", name: "前鎮機廠", routes: %w[circular_lrt], lon: 120.326042, lat: 22.608478, grade: "輕軌" },
      { id: "kaohsiung_gushan_stabling", name: "鼓山駐車場", routes: %w[circular_lrt], lon: 120.281088, lat: 22.642035, grade: "輕軌" }
    ].freeze

    def self.to_json
      DEPOTS.map { |depot| serialize_depot(snap_depot_to_routes!(depot)) }
    end

    def self.write_json!(path: Rails.root.join("public/geojson/metro_depots.json"))
      File.write(path, JSON.pretty_generate(to_json))
      puts "Wrote #{path} (#{DEPOTS.length} depots)"
    end

    def self.serialize_depot(depot)
      {
        id: depot[:id],
        name: depot[:name],
        routes: depot[:routes],
        lon: depot[:lon].round(6),
        lat: depot[:lat].round(6),
        grade: depot[:grade]
      }
    end

    def self.snap_depot_to_routes!(depot)
      hint_lon = depot[:lon]
      hint_lat = depot[:lat]
      best_lon = hint_lon
      best_lat = hint_lat
      best_distance = Float::INFINITY

      depot[:routes].each do |route_id|
        path = route_geojson_path(route_id)
        next unless path

        snapped_lon, snapped_lat, distance = nearest_on_route_tracks(hint_lon, hint_lat, path)
        next if distance >= best_distance

        best_distance = distance
        best_lon = snapped_lon
        best_lat = snapped_lat
      end

      depot.merge(lon: best_lon, lat: best_lat)
    end

    def self.route_geojson_path(route_id)
      manifest = JSON.parse(Rails.root.join("public/geojson/routes.json").read)
      entry = manifest.values.flatten.find { |route| route["id"] == route_id }
      return nil unless entry

      Rails.root.join("public#{entry["file"]}")
    end

    def self.nearest_on_route_tracks(lon, lat, path)
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

      best_distance = Float::INFINITY
      best_lon = lon
      best_lat = lat

      lines.each do |coordinates|
        coordinates.each_cons(2) do |start_coord, end_coord|
          snapped_lon, snapped_lat, distance = project_on_segment(lon, lat, start_coord, end_coord)
          next if distance >= best_distance

          best_distance = distance
          best_lon = snapped_lon
          best_lat = snapped_lat
        end
      end

      [ best_lon, best_lat, best_distance ]
    end

    def self.project_on_segment(lon, lat, start_coord, end_coord)
      start_lon, start_lat = start_coord
      end_lon, end_lat = end_coord
      delta_lon = end_lon - start_lon
      delta_lat = end_lat - start_lat

      t = if delta_lon.zero? && delta_lat.zero?
        0.0
      else
        raw = ((lon - start_lon) * delta_lon + (lat - start_lat) * delta_lat) / (delta_lon * delta_lon + delta_lat * delta_lat)
        [ [ raw, 0.0 ].max, 1.0 ].min
      end

      snapped_lon = start_lon + (t * delta_lon)
      snapped_lat = start_lat + (t * delta_lat)
      distance = planar_distance_meters(lon, lat, snapped_lon, snapped_lat)

      [ snapped_lon, snapped_lat, distance ]
    end

    def self.planar_distance_meters(lon_a, lat_a, lon_b, lat_b)
      lat_mid_rad = ((lat_a + lat_b) / 2.0) * Math::PI / 180.0
      delta_lat = (lat_b - lat_a) * 111_320.0
      delta_lon = (lon_b - lon_a) * 111_320.0 * Math.cos(lat_mid_rad)

      Math.sqrt((delta_lat * delta_lat) + (delta_lon * delta_lon))
    end

    private_class_method :serialize_depot, :snap_depot_to_routes!, :route_geojson_path,
                         :nearest_on_route_tracks, :project_on_segment, :planar_distance_meters
  end
end
