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
      # OSM/NLSC yard discovery captures the north/south loop around 七堵; keep the depot throat only.
      "tra_qidu_depot" => { min_lat: 25.092, max_lat: 25.099 },
      # Shared OSM cache also contains the 小碧潭 yard south of 十四張; keep each depot local.
      "shisizhang_depot" => {
        min_lat: 24.982, max_lat: 24.9855, min_lon: 121.5265, max_lon: 121.5305,
        clip_vertices: true
      },
      # NLSC mixes 七張/環狀 corridor and deep storage; keep only the yard south of the elevated branch.
      # Keep yard leads south of the elevated loop bend; exclude deep main-line south of 新店.
      "xindian_depot" => {
        # Keep only the yard lead attached near 小碧潭 station throat.
        max_lat: 24.9725, min_lat: 24.9690, min_lon: 121.5295, max_lon: 121.5335,
        clip_vertices: true
      },
      # Keep SW yard toward 崁頂交流道 (screenshot 19.51.57).
      "tra_chaozhou_depot" => {
        min_lat: 22.528, max_lat: 22.5505, min_lon: 120.528, max_lon: 120.538,
        clip_vertices: true
      },
      # 三峽機廠 south of 龍埔路.
      "sanying_depot" => { min_lat: 24.932, max_lat: 24.940, min_lon: 121.378, max_lon: 121.392 },
      # NLSC discovery also captures the passenger BL corridor and a north yard loop; keep the local throat.
      "nangang_depot" => { min_lon: 121.595, max_lat: 25.054 },
      # Keep the north sidings (screenshot 19.53.33); drop the south spur marked X.
      "tra_fugang_depot" => {
        min_lat: 24.9305, max_lat: 24.9345, min_lon: 121.065, max_lon: 121.085,
        clip_vertices: true
      },
      # OSM stub continues north past 崁頂 toward 淡金公路; keep only the yard west of V11.
      "danhai_depot" => { max_lat: 25.2018, min_lat: 25.1995, min_lon: 121.4315, max_lon: 121.4355 },
      # OSM discovery also captures a disconnected southern yard cluster away from the HSR corridor.
      "hsr_liujia_depot" => { max_lon: 121.0428 },
      # OSM yard discovery also captures the east throat toward 大肚溪; keep the west yard only.
      "hsr_wuri_depot" => { max_lon: 120.618 },
      # OSM yard discovery also captures the southeast throat; keep the northwest yard only.
      "hsr_taibao_depot" => { min_lat: 23.456 },
      # NLSC MRT discovery also captures the 文湖線 passenger corridor west of 南港展覽館;
      # keep the northeast approach into 內湖機廠 (red path north along 環東大道).
      "neihu_depot" => { min_lon: 121.6165, max_lon: 121.623, min_lat: 25.0545, max_lat: 25.0615 },
      # NLSC MRT discovery also captures the 文湖線 passenger corridor west of 動物園.
      "muzha_depot" => { min_lon: 121.579 },
      # NLSC pulls the Daye Rd east loop and far Xinbeitou yards; keep the 復興崗→北投機廠 throat.
      # clip_vertices: approach tracks continue slightly east of the branch; trim instead of dropping.
      "beitou_depot" => {
        min_lon: 121.478,
        max_lon: 121.4915,
        min_lat: 25.134,
        max_lat: 25.1385,
        clip_vertices: true
      }
    }.freeze

    # Drop spur fragments that only duplicate the passenger corridor (need a yard vertex this far off).
    SPUR_OFF_MAIN_MIN_M = {
      "beitou_depot" => 40,
      "xindian_depot" => 35,
      "danhai_depot" => 25
    }.freeze

    # Force depot spurs to join the main line at a known station or junction.
    SPUR_JUNCTION_HINTS = {
      "kaohsiung_circular_depot" => { lon: 120.326042, lat: 22.608478 },
      # Leave the passenger corridor just south of 潮州 before entering the SW yard.
      "tra_chaozhou_depot" => { lon: 120.5359, lat: 22.5483 },
      # On passenger corridor SE of 龍埔 before the river bridge.
      "sanying_depot" => { lon: 121.3895, lat: 24.9362 },
      "danhai_depot" => { lon: 121.43482, lat: 25.2010 },
      "tra_yilan_depot" => { lon: 121.758253, lat: 24.753583 },
      "tra_qidu_depot" => { lon: 121.713831, lat: 25.092014 },
      # Branch east of 水磨坑溪 / 豐年郵局 (screenshot 15.52.02), not the diagonal X south of the post office.
      "beitou_depot" => { lon: 121.4907, lat: 25.13805 },
      "shisizhang_depot" => { lon: 121.52845, lat: 24.98383 },
      # Peel from the southern bend of the 小碧潭 elevated loop into the yard.
      "xindian_depot" => { lon: 121.53148, lat: 24.97128 },
      "qingpu_depot" => { lon: 121.2141381, lat: 25.0137163 },
      "tra_fugang_depot" => { lon: 121.0705, lat: 24.9315 },
      "nangang_depot" => { lon: 121.60385, lat: 25.05184 },
      "tucheng_depot" => { lon: 121.45164, lat: 24.99573 },
      "taichung_beitun_depot" => { lon: 120.71023, lat: 24.18410 },
      "hsr_liujia_depot" => { lon: 121.03858, lat: 24.8019923 },
      "hsr_wuri_depot" => { lon: 120.6146884, lat: 24.0995112 },
      "hsr_taibao_depot" => { lon: 120.3239384, lat: 23.4631241 },
      "muzha_depot" => { lon: 121.57948795924513, lat: 24.99833313676789 },
      # Branch east from 南港展覽館 into 內湖機廠.
      "neihu_depot" => { lon: 121.6175958, lat: 25.055012 }
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
      "hsr_taibao_depot" => [
        197_654_509, 197_654_511, 194_333_560, 194_333_563,
        966_452_493, 966_452_494, 966_452_495, 966_452_496,
        197_654_517, 1_474_733_652, 1_474_733_653, 706_622_436, 197_653_375
      ]
    }.freeze

    # Catalog hints for yards where the marker should sit away from the passenger main line.
    FACILITY_COORDINATE_HINTS = {
      # Northern yard throat along 環東大道 (screenshot 21.32.49 red box).
      "neihu_depot" => { lon: 121.6194, lat: 25.06037 },
      # East side of the 木柵機廠 yard rectangle tracks (screenshot 21.33.31).
      "muzha_depot" => { lon: 121.5855, lat: 25.0014 },
      # Spur tip on continuous yard lead (avoid diagonal closing chord). Marker stays at red circle.
      "beitou_depot" => { lon: 121.48594, lat: 25.13663 },
      "tra_changhua_depot" => { lon: 120.540171, lat: 24.085948 },
      "hsr_yanchao_depot" => { lon: 120.3465, lat: 22.764806 },
      "kaohsiung_north_depot" => { lon: 120.3026, lat: 22.7767 },
      "kaohsiung_south_depot" => { lon: 120.3308, lat: 22.5843 },
      "shisizhang_depot" => { lon: 121.5288, lat: 24.9852 },
      "xindian_depot" => { lon: 121.53148, lat: 24.97128 },
      # Catalog marker sits SW of the yard; pin the facility on the OSM spur throat.
      "qingpu_depot" => { lon: 121.216552, lat: 25.014589 },
      "taichung_beitun_depot" => { lon: 120.7120, lat: 24.1890 },
      "hsr_liujia_depot" => { lon: 121.0412509, lat: 24.8124655 },
      "hsr_wuri_depot" => { lon: 120.6125, lat: 24.1100 },
      "hsr_taibao_depot" => { lon: 120.32375, lat: 23.4755 },
      # North yard throat (screenshot 19.53.33 red box), not the south X.
      "tra_fugang_depot" => { lon: 121.0725, lat: 24.9328 },
      # Yard west of V11 崁頂 (screenshot 11.14.52), not the stub north of 台2.
      "danhai_depot" => { lon: 121.4332, lat: 25.2007 },
      # SW yard toward 崁頂交流道 (screenshot 19.51.57).
      "tra_chaozhou_depot" => { lon: 120.5315, lat: 22.5355 },
      # 三峽機廠 south of 龍埔路 (screenshot 11.14.15).
      "sanying_depot" => { lon: 121.3805, lat: 24.9345 }
    }.freeze

    OMIT_SPUR_IDS = %w[
      tucheng_depot
    ].freeze

    def self.omit_spur?(depot_id)
      OMIT_SPUR_IDS.include?(depot_id)
    end

    def self.junction_hint_for(depot_id)
      SPUR_JUNCTION_HINTS[depot_id]
    end

    def self.facility_coordinates(depot, main_line_strings: nil)
      hint = FACILITY_COORDINATE_HINTS[depot[:id]]
      return { lon: hint[:lon].round(6), lat: hint[:lat].round(6) } if hint

      hint_lon = depot[:lon]
      hint_lat = depot[:lat]
      # Prefer OSM spur network so facility placement matches linkable_line_strings_for_depot.
      spur_lines = osm_line_strings_for_depot(depot[:id])
      spur_lines = nlsc_line_strings_for_depot(depot[:id]) if spur_lines.empty?

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

    def self.osm_line_strings_for_depot(depot_id)
      cache_path = CACHE_DIR.join("#{depot_id}.json")
      return [] unless cache_path.exist?

      lines = JSON.parse(cache_path.read).fetch("line_strings", [])
      apply_spur_line_bounds(depot_id, lines)
    end

    def self.nlsc_line_strings_for_depot(depot_id)
      lines = NlscRailwayCatalog.line_strings_for_depot(depot_id)
      return [] if lines.empty?

      apply_spur_line_bounds(depot_id, lines)
    end

    def self.line_strings_for_depot(depot_id)
      osm = osm_line_strings_for_depot(depot_id)
      return osm if osm.any?

      nlsc_line_strings_for_depot(depot_id)
    end

    # Prefer OSM yard throats, then NLSC extracts (NLSC fragments sometimes never snap).
    def self.candidates_for_depot(depot_id)
      candidates = []
      osm = osm_line_strings_for_depot(depot_id)
      candidates << osm if osm.any?
      nlsc = nlsc_line_strings_for_depot(depot_id)
      candidates << nlsc if nlsc.any?
      candidates
    end

    def self.linkable_line_strings_for_depot(
      depot_id,
      main_line_strings:,
      facility_lon:,
      facility_lat:,
      junction_hint: nil
    )
      osm = osm_line_strings_for_depot(depot_id)
      nlsc = nlsc_line_strings_for_depot(depot_id)
      # OSM first, then OSM+NLSC (bridges disconnected yard clusters), then NLSC alone.
      candidates = []
      candidates << osm if osm.any?
      candidates << (osm + nlsc) if osm.any? && nlsc.any?
      candidates << nlsc if nlsc.any?

      candidates.each do |spur_line_strings|
        spur_line_strings = filter_off_main_spur_lines(
          spur_line_strings,
          main_line_strings,
          min_distance_m: SPUR_OFF_MAIN_MIN_M[depot_id]
        )
        next if spur_line_strings.empty?

        link = TrackGeometry.depot_link_coordinates_for_point(
          facility_lon,
          facility_lat,
          main_line_strings,
          spur_line_strings: spur_line_strings,
          junction_reference_lon: junction_hint&.dig(:lon),
          junction_reference_lat: junction_hint&.dig(:lat)
        )
        next unless link

        # Reject stub links that never leave the junction toward the facility
        # (disconnected OSM fragments can still produce a short truthy path).
        tail = TrackGeometry.planar_distance_meters(
          link.last[0], link.last[1], facility_lon, facility_lat
        )
        next if tail > TrackGeometry::FACILITY_ENDPOINT_SNAP_M * 2

        return spur_line_strings
      end

      []
    end

    def self.filter_off_main_spur_lines(lines, main_line_strings, min_distance_m:)
      return lines if min_distance_m.nil? || main_line_strings.nil? || main_line_strings.empty?

      lines.select do |line|
        line.any? do |lon, lat|
          TrackGeometry.nearest_on_line_strings(lon, lat, main_line_strings)[2] > min_distance_m
        end
      end
    end

    def self.apply_spur_line_bounds(depot_id, lines)
      bounds = SPUR_LINE_BOUNDS[depot_id]
      return lines unless bounds

      if bounds[:clip_vertices]
        return lines.filter_map do |line|
          clipped = line.select do |lon, lat|
            lon_ok = (!bounds[:max_lon] || lon <= bounds[:max_lon]) &&
              (!bounds[:min_lon] || lon >= bounds[:min_lon])
            lat_ok = (!bounds[:max_lat] || lat <= bounds[:max_lat]) &&
              (!bounds[:min_lat] || lat >= bounds[:min_lat])
            lon_ok && lat_ok
          end
          next if clipped.length < 2
          next if bounds[:require_max_lat_above] && clipped.map { |point| point[1] }.max < bounds[:require_max_lat_above]

          clipped
        end
      end

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
        if NlscRailwayCatalog.refresh_depot_cache!(depot)
          next
        end

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
