# frozen_string_literal: true

require "json"

module Geojson
  # Cached OSM yard / depot spur geometry for off-main-line maintenance facilities.
  module DepotSpurCatalog
    CACHE_DIR = Rails.root.join("lib/geojson/fallback_tracks/depot_spurs")

    # Trim cached spur geometry when OSM discovery pulls in unrelated nearby tracks.
    SPUR_LINE_BOUNDS = {
      # OSM yard discovery also captures the RK1 extension north of 岡山高醫.
      "kaohsiung_north_depot" => { max_lat: 22.7825 },
      # OSM yard discovery also captures yard tracks south of 新左營.
      "hsr_zuoying_depot" => { require_max_lat_above: 22.6875 },
      # OSM yard discovery also captures a southern siding near 高雄國際機場.
      "kaohsiung_south_depot" => { min_lat: 22.578 },
      # OSM yard discovery also captures a southern siding away from C37 輕軌機廠.
      "kaohsiung_circular_depot" => { min_lat: 22.6084 },
      # OSM yard discovery captures the north/south loop around 七堵; keep the depot throat only.
      "tra_qidu_depot" => { min_lat: 25.092, max_lat: 25.099 },
      # Shared OSM cache also contains the 小碧潭 yard south of 十四張; keep each depot local.
      "shisizhang_depot" => { min_lat: 24.982 },
      "xindian_depot" => { max_lat: 24.973, min_lon: 121.525 },
      # OSM discovery also captures a disconnected southern yard cluster away from the HSR corridor.
      "hsr_liujia_depot" => { max_lon: 121.0428 },
      # OSM yard discovery also captures the east throat toward 大肚溪; keep the west yard only.
      "hsr_wuri_depot" => { max_lon: 120.618 },
      # OSM yard discovery also captures the southeast throat; keep the northwest yard only.
      "hsr_taibao_depot" => { min_lat: 23.456 }
    }.freeze

    # Force depot spurs to join the main line at a known station or junction.
    SPUR_JUNCTION_HINTS = {
      "kaohsiung_circular_depot" => { lon: 120.326042, lat: 22.608478 },
      "tra_chaozhou_depot" => { lon: 120.5360618, lat: 22.5499793 },
      "tra_yilan_depot" => { lon: 121.758253, lat: 24.753583 },
      "tra_qidu_depot" => { lon: 121.713831, lat: 25.092014 },
      "beitou_depot" => { lon: 121.48924, lat: 25.13845 },
      "shisizhang_depot" => { lon: 121.5276, lat: 24.9844835 },
      "xindian_depot" => { lon: 121.5305976, lat: 24.9712591 },
      "qingpu_depot" => { lon: 121.2141381, lat: 25.0137163 },
      "tra_fugang_depot" => { lon: 121.062, lat: 24.929 },
      "hsr_liujia_depot" => { lon: 121.03858, lat: 24.8019923 },
      "hsr_wuri_depot" => { lon: 120.6146884, lat: 24.0995112 },
      "hsr_taibao_depot" => { lon: 120.3239384, lat: 23.4631241 }
    }.freeze

    # Optional OSM way overrides when automatic discovery returns too much noise.
    SPUR_WAY_IDS = {
      "beitou_depot" => [ 131_648_177, 131_648_179, 131_648_181, 131_648_183, 131_648_184 ],
      "nangang_depot" => [ 189_061_485 ],
      "tucheng_depot" => [ 499_763_106, 818_792_051, 818_792_052, 818_792_053, 818_792_054, 818_792_055 ],
      "muzha_depot" => [
        713_800_29, 517_465_498, 517_465_499, 517_465_496, 517_465_495, 517_465_494,
        517_465_493, 517_465_492, 517_465_491, 517_465_490, 499_758_762
      ],
      "hsr_yanchao_depot" => [
        104_822_960, 104_822_963, 104_822_969, 104_822_972, 104_822_981, 104_822_989, 104_822_990,
        104_822_993, 104_823_003, 104_823_021, 104_823_090, 104_823_099, 104_823_102, 104_823_103,
        104_823_118, 104_823_120, 104_823_122, 104_823_126, 500_539_448, 500_539_449, 500_539_450,
        500_541_174, 870_561_403, 870_561_404, 870_561_405, 870_561_406, 870_561_407, 870_561_408,
        870_561_409, 870_561_410, 870_561_411, 870_561_412, 1_342_641_743, 1_342_641_744
      ],
      "skytrain_depot" => [ 256_726_319, 256_726_320 ],
      "hsr_taibao_depot" => [
        197_654_509, 197_654_511, 194_333_560, 194_333_563,
        966_452_493, 966_452_494, 966_452_495, 966_452_496,
        197_654_517, 1_474_733_652, 1_474_733_653, 706_622_436, 197_653_375
      ]
    }.freeze

    # Catalog hints for yards where the marker should sit away from the passenger main line.
    FACILITY_COORDINATE_HINTS = {
      "neihu_depot" => { lon: 121.621417, lat: 25.057639 },
      "tra_changhua_depot" => { lon: 120.540171, lat: 24.085948 },
      "hsr_yanchao_depot" => { lon: 120.3465, lat: 22.764806 },
      "kaohsiung_north_depot" => { lon: 120.3026, lat: 22.7767 },
      "shisizhang_depot" => { lon: 121.5288, lat: 24.9852 },
      "xindian_depot" => { lon: 121.530598, lat: 24.971259 },
      "tra_fugang_depot" => { lon: 121.0849875, lat: 24.9344212 },
      "hsr_liujia_depot" => { lon: 121.0412509, lat: 24.8124655 },
      "hsr_wuri_depot" => { lon: 120.6125, lat: 24.1100 },
      "hsr_taibao_depot" => { lon: 120.32375, lat: 23.4755 }
    }.freeze

    def self.junction_hint_for(depot_id)
      SPUR_JUNCTION_HINTS[depot_id]
    end

    def self.facility_coordinates(depot, main_line_strings: nil)
      hint = FACILITY_COORDINATE_HINTS[depot[:id]]
      return { lon: hint[:lon].round(6), lat: hint[:lat].round(6) } if hint

      hint_lon = depot[:lon]
      hint_lat = depot[:lat]
      spur_lines = line_strings_for_depot(depot[:id])

      if spur_lines.any? && main_line_strings&.any?
        point = TrackGeometry.facility_point_on_spur_network(
          hint_lon, hint_lat, spur_lines, main_line_strings
        )
        return { lon: point[0].round(6), lat: point[1].round(6) }
      end

      if spur_lines.any?
        points = spur_lines.flatten(1)
        return {
          lon: (points.sum { |coord| coord[0] } / points.length).round(6),
          lat: (points.sum { |coord| coord[1] } / points.length).round(6)
        }
      end

      { lon: hint_lon.round(6), lat: hint_lat.round(6) }
    end

    def self.line_strings_for_depot(depot_id)
      cache_path = CACHE_DIR.join("#{depot_id}.json")
      return [] unless cache_path.exist?

      lines = JSON.parse(cache_path.read).fetch("line_strings", [])
      apply_spur_line_bounds(depot_id, lines)
    end

    def self.apply_spur_line_bounds(depot_id, lines)
      bounds = SPUR_LINE_BOUNDS[depot_id]
      return lines unless bounds

      lines.select do |line|
        lats = line.map { |point| point[1] }
        lons = line.map { |point| point[0] }
        lat_ok = !bounds[:max_lat] || lats.max <= bounds[:max_lat]
        lat_ok &&= !bounds[:min_lat] || lats.min >= bounds[:min_lat]
        lat_ok &&= !bounds[:require_max_lat_above] || lats.max >= bounds[:require_max_lat_above]
        lat_ok &&= !bounds[:max_lon] || lons.max <= bounds[:max_lon]
        lat_ok &&= !bounds[:min_lon] || lons.min >= bounds[:min_lon]
        lat_ok
      end
    end

    def self.refresh_cache!(depots: MetroDepotCatalog::DEPOTS)
      FileUtils.mkdir_p(CACHE_DIR)

      depots.each do |depot|
        refresh_depot!(depot)
        sleep 0.5
      end
    end

    def self.refresh_depot!(depot)
      way_ids = SPUR_WAY_IDS[depot[:id]]
      ways = if way_ids&.any?
        way_ids.filter_map { |way_id| fetch_way_element(way_id) }
      else
        radius_m = depot[:id].start_with?("hsr_") ? 2_500 : 1_500
        discover_spur_ways(depot[:lat], depot[:lon], radius_m: radius_m)
      end

      line_strings = stitch_way_elements(ways)
      return if line_strings.empty?

      payload = {
        depot_id: depot[:id],
        osm_way_ids: ways.map { |way| way["id"] },
        line_strings: line_strings
      }
      File.write(CACHE_DIR.join("#{depot[:id]}.json"), JSON.pretty_generate(payload))
      puts "Wrote #{depot[:id]} (#{line_strings.length} strings, #{line_strings.sum(&:length)} points)"
    end

    def self.discover_spur_ways(lat, lon, radius_m: 1_500)
      query = <<~QL.squish
        [out:json][timeout:90];
        (
          way(around:#{radius_m},#{lat},#{lon})["railway"="depot"];
          way(around:#{radius_m},#{lat},#{lon})["railway"]["service"="yard"];
          way(around:#{radius_m},#{lat},#{lon})["railway"]["service"="siding"];
        );
        out geom tags;
      QL

      Geojson::OsmRouteExtractor.new(relation_id: 0).send(:post_overpass, query)
        .fetch("elements", [])
        .select { |element| element["type"] == "way" && element["geometry"] }
    rescue StandardError => error
      warn "Depot spur discovery failed near #{lat},#{lon}: #{error.message}"
      []
    end

    def self.fetch_way_element(way_id)
      elements = OsmRouteExtractor.fetch_way_elements(way_id)
      elements.first
    rescue StandardError => error
      warn "Depot spur way #{way_id} fetch failed: #{error.message}"
      nil
    end

    def self.stitch_way_elements(ways)
      return [] if ways.empty?

      stitcher = OsmRouteExtractor.new(relation_id: 0)
      stitcher.stitch_line_strings(ways)
        .map { |coords| coords.map { |lon, lat| [ lon, lat ] } }
    rescue StandardError
      ways.map { |way| way["geometry"].map { |point| [ point["lon"], point["lat"] ] } }
    end

    private_class_method :discover_spur_ways, :fetch_way_element, :stitch_way_elements
  end
end
