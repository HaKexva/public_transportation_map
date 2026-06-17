# frozen_string_literal: true

require "json"

module Geojson
  # Metro maintenance depots (機廠). Catalog lon/lat are the facility locations.
  # Linked routes gain depot_spur geometry when rebuilt (see MetroLineBuilder).
  module MetroDepotCatalog
    DEPOTS = [
      { id: "beitou_depot", name: "北投機廠", routes: %w[tamsui_xinyi], lon: 121.483955, lat: 25.1357899, grade: "五級" },
      {
        id: "xindian_depot",
        name: "新店機廠",
        routes: %w[songshan_xindian xiaobitan_branch],
        track_on: "xiaobitan_branch",
        lon: 121.5308,
        lat: 24.9715,
        grade: "三級"
      },
      { id: "nangang_depot", name: "南港機廠", routes: %w[bannan], lon: 121.6075, lat: 25.0512, grade: "三級" },
      { id: "tucheng_depot", name: "土城機廠", routes: %w[bannan], lon: 121.4483, lat: 24.9910, grade: "四級" },
      { id: "zhonghe_depot", name: "中和機廠", routes: %w[zhonghe_xinlu], lon: 121.508814, lat: 24.990250, grade: "一級" },
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
      { id: "kaohsiung_gushan_stabling", name: "鼓山駐車場", routes: %w[circular_lrt], lon: 120.281088, lat: 22.642035, grade: "輕軌" },
      { id: "hsr_yanchao_depot", name: "燕巢總機廠", routes: %w[taiwan_hsr], lon: 120.361, lat: 22.773, grade: "總機廠" },
      { id: "hsr_wuri_depot", name: "烏日維修基地", routes: %w[taiwan_hsr], lon: 120.615, lat: 24.098, grade: "維修基地" },
      { id: "hsr_liujia_depot", name: "六家維修基地", routes: %w[taiwan_hsr], lon: 121.039, lat: 24.807, grade: "維修基地" },
      { id: "hsr_taibao_depot", name: "太保維修基地", routes: %w[taiwan_hsr], lon: 120.332, lat: 23.459, grade: "維修基地" },
      { id: "hsr_zuoying_depot", name: "左營維修基地", routes: %w[taiwan_hsr], lon: 120.318, lat: 22.682, grade: "維修基地" },
      { id: "tra_shulin_depot", name: "樹林調車場", routes: %w[western_trunk_north], lon: 121.418, lat: 24.988, grade: "調車場" },
      { id: "tra_qidu_depot", name: "七堵機務段", routes: %w[western_trunk_north yilan_line], lon: 121.716, lat: 25.096, grade: "機務段" },
      { id: "tra_fugang_depot", name: "富岡機廠", routes: %w[western_trunk_north], lon: 121.082, lat: 24.928, grade: "機廠" },
      { id: "tra_changhua_depot", name: "彰化機務段", routes: %w[mountain_line sea_line western_trunk_south], lon: 120.5382, lat: 24.0816, grade: "機務段" },
      { id: "tra_chaozhou_depot", name: "潮州機廠", routes: %w[pingtung_line western_trunk_south], lon: 120.542, lat: 22.5505, grade: "機廠" },
      { id: "tra_hualien_depot", name: "花蓮機務段", routes: %w[beihui_line taidong_line], lon: 121.603036, lat: 23.995747, grade: "機務段" },
      { id: "tra_taitung_depot", name: "臺東機務分段", routes: %w[taidong_line], lon: 121.1224316, lat: 22.7934597, grade: "機務段" },
      { id: "tra_yilan_depot", name: "宜蘭機務分段", routes: %w[yilan_line], lon: 121.762, lat: 24.751, grade: "機務段" },
      { id: "maokong_depot", name: "貓空纜車維修區", routes: %w[maokong_gondola], lon: 121.5763, lat: 24.996, grade: "維修區" },
      { id: "skytrain_depot", name: "航廈電車維修區", routes: %w[taoyuan_airport_skytrain], lon: 121.238, lat: 25.077, grade: "維修區" },
      { id: "sun_moon_ropeway_depot", name: "日月潭纜車維修區", routes: %w[sun_moon_ropeway], lon: 120.951, lat: 23.860, grade: "維修區" }
    ].freeze

    def self.depots_for_route(route_id)
      DEPOTS.select { |depot| depot_track_route_id(depot) == route_id }
    end

    def self.depot_track_route_id(depot)
      depot[:track_on] || depot[:routes].first
    end

    def self.to_json
      DEPOTS.map { |depot| serialize_depot(depot) }
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
        grade: depot[:grade],
        track_links: track_links_for_depot(depot)
      }.compact
    end

    def self.track_links_for_depot(depot)
      link_route_ids = depot[:track_on] ? Array(depot[:track_on]) : depot[:routes]

      link_route_ids.filter_map do |route_id|
        path = route_geojson_path(route_id)
        next unless path

        line_strings = TrackGeometry.route_line_strings_from_geojson(path)
        next if line_strings.empty?

        lon = depot[:lon].round(6)
        lat = depot[:lat].round(6)
        coordinates = TrackGeometry.depot_link_coordinates_for_point(lon, lat, line_strings)
        next unless coordinates

        coordinates[-1] = [ lon, lat ]
        { route_id: route_id, coordinates: coordinates }
      end
    end

    def self.route_geojson_path(route_id)
      manifest = JSON.parse(Rails.root.join("public/geojson/routes.json").read)
      entry = manifest.values.flatten.find { |route| route["id"] == route_id }
      return nil unless entry

      Rails.root.join("public#{entry["file"]}")
    end

    private_class_method :serialize_depot, :track_links_for_depot, :route_geojson_path
  end
end
