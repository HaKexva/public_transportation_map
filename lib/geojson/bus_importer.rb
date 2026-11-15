# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"

module Geojson
  class BusImporter
    OUTPUT_SUBDIR = "bus"
    Result = Data.define(:routes, :skipped)

    PALETTE = %w[
      #0B7A3E #2563eb #dc2626 #d97706 #7c3aed #0891b2 #db2777
      #4f46e5 #ea580c #0f766e #9333ea #be123c #0369a1
      #65a30d #c2410c #1d4ed8 #a21caf #0e7490 #b91c1c
      #15803d #7c2d12 #1e3a8a #6b21a8 #155e75 #9f1239
      #3f6212 #92400e #3730a3 #701a75 #134e4a #9f1239
      #166534 #b45309 #1e40af #86198f #115e59 #9a3412
    ].freeze

    def self.import!(city_id:, series: nil, client: nil, rewrite_manifest: true, prune_stale: false, only_slugs: nil)
      new(
        city_id: city_id,
        series: series,
        client: client,
        rewrite_manifest: rewrite_manifest,
        prune_stale: prune_stale,
        only_slugs: only_slugs
      ).import!
    end

    # Import specific RouteUID rows via PTX (or any TdxClient-compatible client).
    # ROUTE_UIDS=NWT18288,TXG2513 bin/rails geojson:bus_route_uids CITY=NewTaipei
    def self.import_route_uids!(city_id:, route_uids:, client: nil, rewrite_manifest: true)
      new(city_id:, client:, rewrite_manifest:, prune_stale: false).import_route_uids!(route_uids)
    end

    def initialize(city_id:, series: nil, client: nil, rewrite_manifest: true, prune_stale: false, only_slugs: nil)
      @city = Geojson::BusCatalog.find(city_id)
      raise ArgumentError, "Unknown bus city: #{city_id}" unless @city

      @series = series.to_s.presence
      @client = client
      @rewrite_manifest = rewrite_manifest
      @prune_stale = prune_stale && only_slugs.nil?
      @only_slugs = only_slugs&.map(&:to_s)&.to_set
    end

    def import!
      client = @client || Transit::TdxClient.new(ignore_breaker: true)
      if client.respond_to?(:configured?) && !client.configured?
        raise Transit::TdxClient::ConfigurationError, "TDX_CLIENT_ID and TDX_CLIENT_SECRET are required"
      end

      @client = client
      routes = @client.fetch_all(self.class.route_path_for(@city))
      shapes = @client.fetch_all(self.class.shape_path_for(@city))
      stop_of_routes = @client.fetch_all(self.class.stop_of_route_path_for(@city))

      skipped = []
      built = []
      shapes_by_uid = Array(shapes).group_by { |shape| shape["RouteUID"].to_s }
      stops_by_uid = Array(stop_of_routes).group_by { |row| row["RouteUID"].to_s }

      self.class.grouped_routes(routes, city: @city, series: @series).each do |slug, group, distinguish_via, unlabeled_via|
        next if @only_slugs && !@only_slugs.include?(slug)

        collections = group.filter_map do |route|
          uid = route["RouteUID"].to_s
          shape_rows = filter_variant_rows(shapes_by_uid[uid] || [], route)
          stop_rows = filter_variant_rows(stops_by_uid[uid] || [], route)
          build_collection(
            route,
            shape_rows,
            stop_rows,
            distinguish_via:,
            unlabeled_via:
          )
        end
        if collections.empty?
          skipped.concat(group.map { |route| route_label(route) })
          next
        end

        collection = merge_collections(collections, slug)
        built << slug
        write_collection!(collection)
      end

      prune_stale_city_files!(built) if @prune_stale
      merge_night_routes!
      Geojson::BusTerminusLines.apply!(city_id: @city.id)
      rewrite_bus_indexes! if @rewrite_manifest && built.any?
      Result.new(routes: built, skipped: skipped)
    end

    def import_route_uids!(route_uids)
      client = @client || Transit::PtxClient.new
      @client = client

      skipped = []
      built = []

      Array(route_uids).map(&:to_s).reject(&:blank?).uniq.each do |uid|
        filter = "RouteUID eq '#{uid}'"
        routes = @client.fetch_all(self.class.route_path_for(@city), query: { "$filter" => filter })
        if routes.empty?
          skipped << uid
          next
        end

        shapes = @client.fetch_all(self.class.shape_path_for(@city), query: { "$filter" => filter })
        stop_of_routes = @client.fetch_all(self.class.stop_of_route_path_for(@city), query: { "$filter" => filter })
        shapes_by_uid = Array(shapes).group_by { |shape| shape["RouteUID"].to_s }
        stops_by_uid = Array(stop_of_routes).group_by { |row| row["RouteUID"].to_s }

        self.class.grouped_routes(routes, city: @city).each do |slug, group, distinguish_via, unlabeled_via|
          collections = group.filter_map do |route|
            route_uid = route["RouteUID"].to_s
            shape_rows = filter_variant_rows(shapes_by_uid[route_uid] || [], route)
            stop_rows = filter_variant_rows(stops_by_uid[route_uid] || [], route)
            build_collection(
              route,
              shape_rows,
              stop_rows,
              distinguish_via:,
              unlabeled_via:
            )
          end
          if collections.empty?
            skipped.concat(group.map { |route| route_label(route) })
            next
          end

          collection = merge_collections(collections, slug)
          built << slug
          write_collection!(collection)
        end
      end

      merge_night_routes!
      Geojson::BusTerminusLines.apply!(city_id: @city.id)
      rewrite_bus_indexes! if @rewrite_manifest && built.any?
      Result.new(routes: built.uniq, skipped: skipped)
    end

    def merge_night_routes!
      subdir = Geojson::BusLayout.subdir_for(@city.id)
      return if subdir.blank?

      dir = Geojson::BusLayout.bus_root.join(subdir)
      Geojson::BusNightMerger.process_city_dir!(dir) if dir.exist?
    end

    def rewrite_bus_indexes!
      Geojson::RoutesManifestWriter.write!
      Geojson::BusStopIndexWriter.write!
      Geojson::BusDepotWriter.write!
    end

    def self.route_path_for(city)
      return "v2/Bus/Route/InterCity" if city.kind == :intercity

      "v2/Bus/Route/City/#{city.tdx_city}"
    end

    def self.shape_path_for(city)
      return "v2/Bus/Shape/InterCity" if city.kind == :intercity

      "v2/Bus/Shape/City/#{city.tdx_city}"
    end

    def self.stop_of_route_path_for(city)
      return "v2/Bus/StopOfRoute/InterCity" if city.kind == :intercity

      "v2/Bus/StopOfRoute/City/#{city.tdx_city}"
    end

    # Yields [slug, routes, distinguish_via, unlabeled_via] for each import group.
    def self.grouped_routes(routes, city:, series: nil)
      return grouped_intercity_routes(routes, series:) if city.kind == :intercity

      collapse_extra_digits = true
      selected = Array(routes).select { |route|
        name = route_name_zh(route)
        series_match?(name, series: series, city:) && !test_route_name?(name)
      }
      groups = []

      selected.group_by { |route|
        public_ref(route_name_zh(route).presence || route["RouteID"].to_s, collapse_extra_digits:, city:)
      }.each do |_ref, numbered|
        numbered = select_listed_routes(numbered, collapse_extra_digits:)
        via_labels = numbered.map { |route| variant_label(route).to_s }
        distinguish_via = via_labels.uniq.size > 1
        unlabeled_via = distinguish_via ? unlabeled_trunk_via(via_labels) : nil

        numbered.flat_map { |route| detour_variants(with_route_alias(route)) }
          .map { |route| with_alias_main_label(route) }
          .group_by { |route| slug_for(route, city:, distinguish_via:, unlabeled_via:) }.each do |slug, group|
          groups << [ slug, group, distinguish_via, unlabeled_via ]
        end
      end

      groups
    end

    DETOUR_PATTERN = /繞駛|繞經/
    # SubRoutes to draw as their own variant that the 繞駛/繞經 pattern misses,
    # by full SubRouteName: trip extensions (237經政大校區 loops through the
    # campus; 237不經政大校區 is the base, shown as 本線), 經/不經 detours
    # (903不經三總 is the skip; 903經三總 stays the plain route), short detour
    # labels (249繞崁頂 is the trip that skips 崁頂; 本線 is the one that goes
    # via 崁頂) and branches run by another operator (306(大都會) ends at 舊莊
    # instead of 凌雲五村). main_label names the remaining plain variant.
    SUBROUTE_SPLITS = {
      "237經政大校區" => { label: "延駛政大校區", main_label: "本線" },
      "542路延駛民族西路" => { label: "延駛民族西路", main_label: "本線" },
      "559繞駛男女五舍" => { label: "繞駛陽明交大五舍" },
      # eBus 「①繞民權路」; TDX SubRouteName is the short 「576繞」.
      "576繞" => { label: "繞駛民權路", main_label: "不繞駛民權路" },
      # 981繞 via 三鶯轉運站; plain 981 skips it. TDX SubRouteName is 「981繞」.
      "981繞" => { label: "繞駛三鶯轉運站", main_label: "不繞駛三鶯轉運站" },
      # 616經黎明 stops at 黎明技術學院; 616路 stays on 泰山路.
      "616經黎明" => { label: "繞駛黎明技術學院", main_label: "不繞駛黎明技術學院" },
      # eBus 部分班次經天母國中; TDX SubRouteName is 「紅19經天母國中」.
      "紅19經天母國中" => { label: "繞駛天母國中", main_label: "本線" },
      # eBus 部分班次繞駛臺北港行政大樓; TDX 「紅22台北港去／返」(車機 rows ignored).
      "紅22台北港去" => { label: "繞駛台北港", main_label: "本線" },
      "紅22台北港返" => { label: "繞駛台北港", main_label: "本線" },
      # eBus 部分班次未進漁人碼頭（淡海↔捷運淡水站）; 車機 rows ignored.
      "紅26未進漁人碼頭" => { label: "不經漁人碼頭", main_label: "本線" },
      "紅26未進漁人碼頭去" => { label: "不經漁人碼頭", main_label: "本線" },
      "紅26未進漁人碼頭返" => { label: "不經漁人碼頭", main_label: "本線" },
      # eBus ①繞淡水商工; main via 勤家捷奏／龍騰／鳳翔（國家新都一帶）.
      "紅37繞淡水商工新市站" => { label: "繞駛淡水商工", main_label: "國家新都" },
      "紅37繞淡水商工捷運淡水站" => { label: "繞駛淡水商工", main_label: "國家新都" },
      # eBus 部分班次經復興北路（五常街口／下埤里／臺北漁市）; plain stays on 民權東路.
      "紅50經復興北路" => { label: "繞駛復興北路", main_label: "本線" },
      # eBus 部分班次經中鼎第二總部大樓／遠雄商舟大樓; TDX 去／返 SubRoutes (預約公車 ignored).
      "紅68去程經中鼎大樓" => { label: "繞駛中鼎第二總部大樓、遠雄商舟大樓", main_label: "本線" },
      "紅68返程經中鼎大樓" => { label: "繞駛中鼎第二總部大樓、遠雄商舟大樓", main_label: "本線" },
      # eBus 繞興福寮66巷; TDX SubRouteName is 「631繞」.
      "631繞" => { label: "繞駛興福寮66巷", main_label: "不繞駛興福寮66巷" },
      # 837副繞 inserts 竹林慈玄宮 between 馬偕醫院 and 民權路3巷口.
      "837副繞" => { label: "繞駛竹林慈玄宮", main_label: "不繞駛竹林慈玄宮" },
      # 837區: most trips on the plain loop; some via 竿蓁二街福德宮 or 紅樹林路.
      "837區經竿蓁二街福德宮" => { label: "繞駛竿蓁二街福德宮", main_label: "本線" },
      "837區經紅樹林路" => { label: "繞駛紅樹林路", main_label: "本線" },
      # 819副 ends at 雙溪口; 819副延 continues 外按橋→石碇區公所→石碇.
      "819副延" => { label: "延駛石碇", main_label: "本線" },
      # eBus 「①繞駛阿南坑、貴興路」; TDX 「847繞」(weekday 07:00/10:00/16:00).
      "847繞" => { label: "繞駛阿南坑、貴興路", main_label: "不繞駛阿南坑、貴興路" },
      # 847區繞: weekday 09/11/13/15 via 土城醫院 (城林橋／捷運土城站).
      "847區繞" => { label: "繞駛土城醫院", main_label: "不繞駛土城醫院" },
      # 851: plain to 鶯歌高職; 不經二甲 skips 尖山國中／國中街 inbound;
      # 延駛邱厝巷 continues past 鶯歌高職 to 邱厝巷.
      "851不經二甲" => { label: "不經二甲", main_label: "本線" },
      "851延駛邱厝巷" => { label: "延駛邱厝巷", main_label: "本線" },
      # 917: plain from 鶯歌火車站; 917延 from 捷運鶯歌車站(新北市美術館).
      "917延" => { label: "美術館發車", main_label: "鶯歌車站發車" },
      # Event-day outbound of the museum start; keep off the 鶯歌車站 file.
      "917延活動專車(返程不停靠)" => { label: "美術館發車", main_label: "鶯歌車站發車" },
      # 918 eBus ①三民路不繞黎明 ②不繞黎明和三民路 ③延駛三民路 ④返程不繞黎明與三民路.
      # Plain 918 keeps 黎明技術學院 and the 崇光／三民路 end.
      "918三民路" => { label: "繞駛三民路", main_label: "本線" },
      "918三民路不繞黎明" => { label: "繞駛三民路、不經黎明", main_label: "本線" },
      "918不繞黎明和三民路" => { label: "不經黎明、不繞三民路", main_label: "本線" },
      "918返程不繞黎明與三民路" => { label: "返程不經黎明、不繞三民路", main_label: "本線" },
      # eBus 「①寵物公車」: same stops as plain 859; Sat/Sun/holiday only.
      "859寵物公車" => { label: "寵物公車" },
      # eBus 「①寵物公車」／狗狗公車: same stops as plain 895; holiday timetable.
      "895寵物公車" => { label: "寵物公車" },
      # eBus 「①行經八勢路一段」: inbound from 八勢路一段; plain continues to 八勢一街／紅樹林路.
      "868行經八勢路一段" => { label: "繞駛八勢路" },
      # TDX 「878延淡水商工」: continues past 捷運淡水站 to 淡水商工／輕軌新市一路站.
      "878延淡水商工" => { label: "延駛淡水商工", main_label: "本線" },
      # eBus 「①行經台北灣」: via 台北灣社區／星海別墅 instead of 大庄／濱海輕軌.
      "881行經台北灣" => { label: "繞駛台北灣社區" },
      # eBus 「①單向繞駛」weekday 06:40 via 大成路／學勤路; TDX 「705繞」.
      # 寒暑假該班改走本線，不另建季節變體。
      "705繞" => { label: "單向繞駛" },
      # 657經海山拖吊場 is the tow-yard branch; the plain SubRoute is 本線.
      "657經海山拖吊場" => { label: "海山拖吊場", main_label: "本線" },
      # TDX short forms: 「592繞惠國市場」「592延耕莘醫院」(not 繞駛／延駛).
      "592繞惠國市場" => { label: "繞駛惠國市場" },
      "592延耕莘醫院" => { label: "延駛耕莘醫院" },
      # Short turns that skip the 樹林藝文端 (four weekday trips).
      "596崑崙里" => { label: "只到崑崙里" },
      # eBus ①原行駛路線 ②桃園酒廠發至返程桃園酒廠 — short turn skips 體育大學端.
      "967桃園酒廠" => { label: "桃園酒廠發車" },
      # eBus ①941區: weekday 06:50 outbound only to 捷運大坪林站; return empty.
      "941區" => { label: "只到捷運大坪林站" },
      "249繞崁頂" => { label: "不繞崁頂" },
      "306(大都會)" => { label: "往舊莊", operator_id: "800" },
      "903不經三總" => { label: "不繞駛三總" },
      "521不經三總" => { label: "不繞駛三總" },
      "藍20不經三總" => { label: "不繞駛三總" }
    }.freeze
    NAMED_LABEL_PATTERN = /繞駛|繞經|延駛|\A不繞|\A不經|\A返程|\A本線|\A正線\z|\A往|\A只到|\A正新|\A新[民春]\z|\A延和路\z|\A海山拖吊場\z|\A低地板\z|\A非低地板\z|\A寵物公車\z|\A金瓜石\z|\A崁腳\z|\A北基新城\z|\A圳頭\z|\A貢寮衛生所\z|\A十分\z|\A十分寮\z|\A平溪\z|\A正德國中\z|\A直行|\A經正德|\A美術館發車\z|\A鶯歌車站發車\z|\A桃園酒廠發車\z|\A青潭\z|\A大崎腳\z|\A國家新都\z|\A海洋都心\z/
    # A separate TDX route that is really one variant of a parent ref.
    # 657延 runs via 延和路; tdx_ref keeps its own timetable.
    # 790漁港 is the weekday detour via 龜吼漁港 (plain 790 skips it).
    # 791繞貢寮 / 791經貢寮區衛生 are sibling TDX routes of 791 (not 區間車).
    # 930延 starts at 中生橋頭／大崎腳; plain 930 is the 青潭停車場 short turn.
    # main_label names the plain sibling so both show as 930（青潭）／930（大崎腳）.
    ROUTE_ALIASES = {
      "657延" => { ref: "657", label: "延和路", tdx_ref: "657延" },
      "790漁港" => { ref: "790", label: "繞駛龜吼漁港", tdx_ref: "790漁港" },
      "791繞貢寮" => { ref: "791", label: "繞駛貢寮", tdx_ref: "791繞貢寮" },
      "791經貢寮區衛生" => { ref: "791", label: "貢寮衛生所", tdx_ref: "791經貢寮區衛生" },
      "930延" => { ref: "930", label: "大崎腳", main_label: "青潭", tdx_ref: "930延" },
      # Capital 「982直達(新埔站)」; TDX keeps a separate 982直達新埔線 route
      # (新埔↔榮華). Full 982直達 continues to 大坪林 (one weekday trip each way).
      "982直達新埔線" => { ref: "982直達", label: "只到新埔站", tdx_ref: "982直達新埔線" },
      # Sibling of 紅37; skips 勤家捷奏／龍騰／鳳翔 for 海洋都心社區.
      "紅37行經海洋都心社區" => { ref: "紅37", label: "繞駛海洋都心", main_label: "國家新都", tdx_ref: "紅37行經海洋都心社區" }
    }.freeze
    # Outbound×inbound path pairs published as separate 去/返 SubRoutes.
    # 595's 新民／新春 streets can be mixed across the round trip.
    PATH_PAIR_VARIANTS = {
      "595" => [
        { label: "新民", outbound: "595新民去", inbound: "595新民返" },
        { label: "新春", outbound: "595新春去", inbound: "595新春返" },
        { label: "正新民反新春", outbound: "595新民去", inbound: "595新春返" },
        { label: "正新春反新民", outbound: "595新春去", inbound: "595新民返" }
      ],
      # eBus ①不經朱銘美術館… = 低地板班次；本線停平安園／筠園／朱銘／舊機場。
      # 5–10月每日、11–4月僅假日（見 SERVICE_NOTES）。
      "716(台灣好行-皇冠北海岸線)" => [
        { label: "非低地板", outbound: "716捷運淡水站", inbound: "716野柳地質公園" },
        { label: "低地板", outbound: "716捷運淡水站不繞", inbound: "716野柳地質公園不繞" }
      ],
      # Most trips end at 金瓜石; a few weekday trips continue to 水湳洞
      # (eBus ①去水湳洞／②返水湳洞; 假日不行駛水湳洞).
      "788" => [
        { label: "金瓜石", outbound: "788基隆轉運站", inbound: "788金瓜石(黃金博物館)" },
        { label: "延駛水湳洞", outbound: "788去水湳洞", inbound: "788返水湳洞" }
      ],
      # 789 正線國家新城↔崁腳; outbound/inbound SubRouteNames differ.
      "789" => [
        { label: "崁腳", outbound: "789國家新城", inbound: "789崁腳" }
      ],
      # 789區 most trips end at 北基新城; some continue to 圳頭 (ex-888).
      "789區" => [
        { label: "北基新城", outbound: "789區基隆轉運站", inbound: "789區北基新城" },
        { label: "圳頭", outbound: "789區延圳頭去", inbound: "789區延圳頭返" }
      ],
      # 正線 ends at 福隆; 延駛 continues to 馬崗(三貂角燈塔). Without the split,
      # primary_subroute_rows picks the longer 延駛 stop list for plain 791.
      "791" => [
        { label: "正線", outbound: "791國家新城", inbound: "791福隆" },
        { label: "延駛馬崗", outbound: "791延國家新城", inbound: "791延福隆" }
      ],
      # eBus 「①直行中山北路 ②經正德國中」— two full paths, not a mix-and-match.
      # Plain 872 (NWT16627) is a separate route via 淡海／後洲.
      "872經正德國中、直行中山北路" => [
        { label: "經正德國中", outbound: "872經正德國中", inbound: "872經正德國中", ref: "872" },
        { label: "直行中山北路", outbound: "872直行中山北路", inbound: "872直行中山北路", ref: "872" }
      ],
      # eBus 「①繞威遠廟瑞芳 ②③繞水湳洞遊客中心」; 威遠廟 is outbound-only
      # (returns on the plain 和美國小 inbound).
      "886" => [
        { label: "本線", outbound: "886瑞芳", inbound: "886和美國小" },
        { label: "繞駛水湳洞", outbound: "886繞水湳洞遊客中心瑞芳", inbound: "886繞水湳洞遊客中心和美國小" },
        { label: "繞駛威遠廟", outbound: "886繞威遠廟瑞芳", inbound: "886和美國小" }
      ],
      # eBus 「①往劍潭／陽明山 ②往劍潭經文大／往陽明山經文大」— campus loop adds
      # 文化大學一／陽明天主堂; plain keeps 文化大學 on 格致路 only.
      "紅5" => [
        { label: "本線", outbound: "紅5往劍潭", inbound: "紅5往陽明山" },
        { label: "繞駛文化大學", outbound: "紅5往劍潭經文大", inbound: "紅5往陽明山經文大" }
      ],
      # eBus ①–④ outbound (±劍潭/北藝、±小油坑) paired with matching inbound
      # ⑤/⑥ (金山發 never via 劍潭). Four round-trip modes.
      "1717" => [
        {
          label: "本線",
          outbound: "1717(捷運台大醫院站發不經捷運劍潭站不經小油坑服務站)",
          inbound: "1717(金山郵局發不經捷運劍潭站不經小油坑服務站)"
        },
        {
          label: "本線小油坑",
          outbound: "1717(捷運台大醫院站發不經捷運劍潭站經小油坑服務站)",
          inbound: "1717(金山郵局發不經捷運劍潭站經小油坑服務站)"
        },
        {
          label: "本線北藝中心",
          outbound: "1717(捷運台大醫院站發經捷運劍潭站不經小油坑服務站)",
          inbound: "1717(金山郵局發不經捷運劍潭站不經小油坑服務站)"
        },
        {
          label: "本線兩種",
          outbound: "1717(捷運台大醫院站發經捷運劍潭站經小油坑服務站)",
          inbound: "1717(金山郵局發不經捷運劍潭站經小油坑服務站)"
        }
      ]
    }.freeze
    # Seasonal / operator notes stamped onto matching refs (both path-pair siblings).
    SERVICE_NOTES = {
      "716(台灣好行-皇冠北海岸線)" => {
        "zh" => "5–10月每日；11–4月僅假日",
        "en" => "Daily May–Oct; weekends & holidays Nov–Apr"
      }
    }.freeze
    # Capital Bus 「預約公車」side SubRoutes (and sibling TDX `…預` routes with
    # no published shape). Stamp the parent so riders know those trips need booking.
    RESERVATION_PARTIAL_NOTE = {
      "zh" => "部分班次須提前預約",
      "en" => "Some trips require advance booking"
    }.freeze
    RESERVATION_ONLY_NOTE = {
      "zh" => "預約公車，須提前預約",
      "en" => "Reservation bus; book ahead"
    }.freeze
    # 265經中央路（三重） and 265經明德路（大南） are the two full 土城–立法院
    # trunks. 265區 is the short turn, not the main line. tdx_ref keeps the
    # timetable lookup on the original route name.
    TRUNK_LABELS = {
      "265經中央路" => { ref: "265", name: "265（中央主線）", name_en: "265 (Zhongyang Main Line)", tdx_ref: "265經中央路" },
      "265經明德路" => { ref: "265", name: "265（明德主線）", name_en: "265 (Mingde Main Line)", tdx_ref: "265經明德路" }
    }.freeze

    def self.trunk_label(route_name)
      TRUNK_LABELS[route_name.to_s.strip]
    end

    def self.with_route_alias(route)
      spec = ROUTE_ALIASES[route_name_zh(route).strip]
      return route unless spec

      route.merge(
        "_import_ref" => spec[:ref],
        "_import_detour" => spec[:label],
        "_import_tdx_ref" => spec[:tdx_ref]
      )
    end

    # Plain sibling of a ROUTE_ALIASES row (e.g. 930 when 930延 → 大崎腳).
    def self.with_alias_main_label(route)
      return route if route["_import_detour"].present? || route["_import_main_label"].present?

      name = route_name_zh(route).strip
      main_label = ROUTE_ALIASES.each_value.find { |spec|
        spec[:ref] == name && spec[:main_label].present?
      }&.dig(:main_label)
      return route unless main_label

      route.merge("_import_main_label" => main_label)
    end

    def self.schedule_ref(properties)
      properties = properties || {}
      properties["tdx_ref"].presence || properties["ref"].to_s
    end

    def self.subroute_split(label)
      SUBROUTE_SPLITS.find { |_name, split| split[:label] == label }
    end

    # SubRouteNames split away from the plain variant named main_label.
    def self.split_names_for_main(main_label)
      SUBROUTE_SPLITS.select { |_name, split| split[:main_label] == main_label }.keys
    end

    # City routes that run a 繞駛 detour on some trips publish it as a separate
    # SubRoute (e.g. 33 / 33繞駛大道路). Draw each as its own route so the
    # detour does not get merged into the plain path.
    def self.detour_variants(route)
      if (pairs = path_pair_variants(route))
        return pairs
      end

      subs = Array(route["SubRoutes"])
      detours = subs.select { |sub| detour_label(sub, route) }
      return [ route ] if detours.empty?

      # When the unlabelled SubRoutes don't run both ways (e.g. a one-way
      # side service), the single "不繞駛" label is the plain route.
      directions = ->(rows) { rows.map { |sub| sub["Direction"].to_s }.uniq.sort }
      if directions.(subs - detours) != directions.(subs)
        plain = detours.select { |sub| detour_label(sub, route).match?(/\A[不無]/) }
        plain_labels = plain.map { |sub| detour_label(sub, route) }.uniq
        detours -= plain if plain_labels.length == 1
      end

      remainder = subs - detours
      main_label = detours.filter_map { |sub| subroute_split(detour_label(sub, route))&.last&.dig(:main_label) }.first
      # When the split names a 本線, keep the canonical parent / parent路 row —
      # not 去程半 / 預約 side services that may share the extension terminus.
      if main_label.present?
        parent = route_name_zh(route).strip
        canonical = remainder.select { |sub|
          name = route_name_zh(sub.merge("RouteName" => sub["SubRouteName"])).strip
          name == parent || name == "#{parent}路" || name == "#{parent}線"
        }
        remainder = canonical if canonical.any?
      end
      main_uids = remainder.map { |sub| sub["SubRouteUID"].to_s }.reject(&:blank?).uniq
      variants = []
      if main_uids.any?
        main = route.merge("_import_sub_uids" => main_uids, "_import_blank_sub" => true)
        main["_import_main_label"] = main_label if main_label
        variants << main
      end
      detours.group_by { |sub| detour_label(sub, route) }.each do |label, rows|
        variants << route.merge(
          "_import_sub_uids" => rows.map { |row| row["SubRouteUID"].to_s }.reject(&:blank?).uniq,
          "_import_detour" => label
        )
      end
      variants
    end

    def self.detour_label(sub, route)
      name = route_name_zh(sub.merge("RouteName" => sub["SubRouteName"])).strip
      parent = route_name_zh(route).strip
      return unless name.start_with?(parent) && name != parent
      return SUBROUTE_SPLITS.dig(name, :label) if SUBROUTE_SPLITS.key?(name)

      label = name.delete_prefix(parent).strip
      label = label[/[(（]([^()（）]*#{DETOUR_PATTERN}[^()（）]*)[)）]/, 1] || label
      label = label.sub(/(?:去程|返程|往程|回程)半?\z/, "").strip

      # Timetable notes ("平0550 假0600無繞駛") are not a separate path.
      label if label.match?(DETOUR_PATTERN) && !label.match?(/[平假]\s*\d{3,4}/)
    end

    def self.path_pair_variants(route)
      parent = route_name_zh(route).strip
      specs = PATH_PAIR_VARIANTS[parent]
      return unless specs

      by_name = Array(route["SubRoutes"]).group_by { |sub|
        route_name_zh(sub.merge("RouteName" => sub["SubRouteName"])).strip
      }
      specs.filter_map do |spec|
        rows = Array(by_name[spec[:outbound]]) + Array(by_name[spec[:inbound]])
        uids = rows.map { |sub| sub["SubRouteUID"].to_s }.reject(&:blank?).uniq
        next if uids.empty?

        enriched = route.merge("_import_sub_uids" => uids, "_import_detour" => spec[:label])
        enriched["_import_ref"] = spec[:ref] if spec[:ref].present?
        enriched["_import_tdx_ref"] = spec[:tdx_ref] || parent if spec[:ref].present? || spec[:tdx_ref].present?
        enriched
      end.presence
    end

    def self.path_pair_subroute_names(via)
      label = via.to_s
      return if label.blank?

      PATH_PAIR_VARIANTS.each_value do |specs|
        spec = specs.find { |row| row[:label].to_s == label }
        return [ spec[:outbound], spec[:inbound] ] if spec
      end
      nil
    end

    def self.service_note_for(ref, route: nil)
      notes = []
      notes << SERVICE_NOTES[ref.to_s] if SERVICE_NOTES.key?(ref.to_s)
      if (reservation = reservation_note_for(route))
        notes << reservation
      end
      return if notes.empty?

      {
        "zh" => notes.map { |note| note["zh"] }.join("；"),
        "en" => notes.map { |note| note["en"] }.join("; ")
      }
    end

    def self.reservation_note_for(route)
      return unless route

      name = route_name_zh(route).to_s.strip
      return RESERVATION_ONLY_NOTE if name.match?(/預\z|預約/)
      return RESERVATION_PARTIAL_NOTE if reservation_subroute?(route)

      nil
    end

    def self.reservation_subroute?(route)
      Array(route["SubRoutes"]).any? do |sub|
        route_name_zh(sub.merge("RouteName" => sub["SubRouteName"])).to_s.include?("預約")
      end
    end

    # Highway coaches often encode A–J detours as SubRoutes with their own shapes.
    def self.grouped_intercity_routes(routes, series: nil)
      selected = Array(routes).select { |route| series_match?(route_name_zh(route), series: series) }
      groups = []

      selected.each do |route|
        intercity_variant_specs(route).each do |spec|
          next unless series.blank? || series_match?(spec[:ref], series: series) ||
            series_match?(route_name_zh(route), series: series)

          enriched = route.merge(
            "_import_ref" => spec[:ref],
            "_import_sub_uids" => spec[:sub_uids],
            "_import_headsign" => spec[:headsign]
          )
          slug = slug_for(enriched, city: Geojson::BusCatalog.find("InterCity"))
          groups << [ slug, [ enriched ], false, nil ]
        end
      end

      groups
    end

    def self.intercity_variant_specs(route)
      subs = Array(route["SubRoutes"])
      return [ { ref: route_name_zh(route).presence || route["RouteID"].to_s, sub_uids: nil, headsign: nil } ] if subs.empty?

      grouped = subs.group_by { |sub| intercity_subroute_ref(sub, route) }
      grouped.map do |ref, rows|
        {
          ref: ref,
          sub_uids: rows.map { |row| row["SubRouteUID"].to_s }.reject(&:blank?).uniq,
          headsign: rows.filter_map { |row| row["Headsign"].to_s.presence }.first
        }
      end.sort_by { |spec| [ spec[:ref].to_s.length, spec[:ref].to_s ] }
    end

    def self.intercity_subroute_ref(sub, route)
      name = route_name_zh(sub.merge("RouteName" => sub["SubRouteName"]))
      return name if name.present?

      uid = sub["SubRouteUID"].to_s
      parent = route_name_zh(route).presence || route["RouteID"].to_s
      if (match = uid.match(/#{Regexp.escape(parent)}([A-J])\d*\z/i))
        return "#{parent}#{match[1].upcase}"
      end

      parent
    end

    # Planned slug groups for coverage audits (does not require shapes).
    def self.plan_import(routes, city:, series: nil)
      collapse_extra_digits = city.kind != :intercity
      grouped_routes(routes, city:, series:).map do |slug, group, distinguish_via, unlabeled_via|
        {
          slug: slug,
          uids: group.map { |route| route["RouteUID"].to_s },
          gaps: group.map do |route|
            ref = route["_import_ref"].presence ||
              public_ref(route_name_zh(route).presence || route["RouteID"].to_s, collapse_extra_digits:, city:)
            via = if distinguish_via
              via_label = variant_label(route).presence || "其他"
              (unlabeled_via.present? && via_label == unlabeled_via) ? nil : via_label
            end
            label = [ route["RouteUID"], ref, via ].compact.join(" ").strip
            {
              city_id: city.id,
              route_uid: route["RouteUID"].to_s,
              ref: ref,
              label: label,
              slug: slug
            }
          end
        }
      end
    end

    # Same token BusTimedDetours hashes for the campus/main file id.
    CAMPUS_DETOUR_LABEL = "繞駛三總"
    HOSPITAL_SKIP_LABEL = "不繞駛三總"

    def self.slug_for(route, city:, distinguish_via: false, unlabeled_via: nil)
      collapse_extra_digits = city.kind != :intercity
      raw_ref = route["_import_ref"].presence ||
        public_ref(route_name_zh(route).presence || route["RouteID"].to_s, collapse_extra_digits:, city:)
      ref = ref_slug(raw_ref)
      via = if distinguish_via
        via_label = variant_label(route).presence || "其他"
        (unlabeled_via.present? && via_label == unlabeled_via) ? nil : via_label
      end
      via_slug = variant_slug(via)
      detour = route["_import_detour"].to_s
      # 903 / 521 / 藍20: keep the skip on the bare slug (with 福華商場) and put
      # the 經三總 campus path on the same _1652fe7623 sibling timed detours use.
      if detour == HOSPITAL_SKIP_LABEL
        detour = ""
      elsif route["_import_blank_sub"] && hospital_skip_split_route?(route)
        detour = CAMPUS_DETOUR_LABEL
      end
      detour_slug = Digest::SHA1.hexdigest(detour)[0, 10] if detour.present?
      [ city.id.underscore, ref, via_slug, detour_slug ].compact_blank.join("_")
    end

    def self.hospital_skip_split_route?(route)
      route_name = route_name_zh(route).to_s
      SUBROUTE_SPLITS.any? do |sub_name, split|
        split[:label] == HOSPITAL_SKIP_LABEL && sub_name.sub(/不經三總\z/, "") == route_name
      end
    end

    VIA_EN = {
      "祥豐街" => "Xiangfeng St.",
      "中正路" => "Zhongzheng Rd.",
      "大道路" => "Dadao Rd.",
      "本線" => "Main Line",
      "美術館發車" => "from Art Museum",
      "鶯歌車站發車" => "from Yingge Station",
      "繞駛三民路" => "detour via Sanmin Rd.",
      "繞駛三民路、不經黎明" => "detour via Sanmin Rd., skips Lee-Ming Institute of Technology",
      "不經黎明、不繞三民路" => "skips Lee-Ming Institute of Technology and Sanmin Rd.",
      "返程不經黎明、不繞三民路" => "inbound skips Lee-Ming Institute of Technology and Sanmin Rd.",
      "崁頂" => "Kanding",
      "不繞崁頂" => "skips Kanding",
      "往舊莊" => "to Jiuzhuang",
      "不繞駛三總" => "skips Tri-Service General Hospital",
      "三總" => "Tri-Service General Hospital",
      "延駛政大校區" => "extended to NCCU Campus",
      "延駛民族西路" => "extended to Minzu West Road",
      "繞駛陽明交大五舍" => "detour via NYCU Dorm 5",
      "繞駛民權路" => "detour via Minquan Rd.",
      "不繞駛民權路" => "skips Minquan Rd.",
      "繞駛三鶯轉運站" => "detour via Sanying Bus Station",
      "不繞駛三鶯轉運站" => "skips Sanying Bus Station",
      "繞駛北藝中心" => "detour via Taipei Performing Arts Center",
      "繞駛小油坑" => "detour via Xiaoyoukeng",
      "繞駛北藝中心、小油坑" => "detour via Taipei Performing Arts Center & Xiaoyoukeng",
      "本線小油坑" => "Main Line via Xiaoyoukeng",
      "本線北藝中心" => "Main Line via Taipei Performing Arts Center",
      "本線兩種" => "Main Line via Taipei Performing Arts Center & Xiaoyoukeng",
      "繞駛文化大學" => "detour via Chinese Culture University",
      "文化大學" => "Chinese Culture University",
      "繞駛天母國中" => "detour via Tianmu Junior High School",
      "天母國中" => "Tianmu Junior High School",
      "繞駛台北港" => "detour via Taipei Port",
      "台北港" => "Taipei Port",
      "不經漁人碼頭" => "skips Fisherman's Wharf",
      "漁人碼頭" => "Fisherman's Wharf",
      "國家新都" => "Guojia Xindu",
      "繞駛海洋都心" => "detour via Ocean Community",
      "海洋都心" => "Ocean Community",
      "繞駛淡水商工" => "detour via Tamsui Vocational High School",
      "繞駛復興北路" => "detour via Fuxing North Rd.",
      "復興北路" => "Fuxing North Rd.",
      "繞駛中鼎第二總部大樓、遠雄商舟大樓" => "detour via CTCI HQ 2 & Farglory Merchant Building",
      "中鼎第二總部大樓、遠雄商舟大樓" => "CTCI HQ 2 & Farglory Merchant Building",
      "黎明技術學院" => "Lee-Ming Institute of Technology",
      "繞駛黎明技術學院" => "detour via Lee-Ming Institute of Technology",
      "不繞駛黎明技術學院" => "skips Lee-Ming Institute of Technology",
      "興福寮66巷" => "Xingfuliao Ln. 66",
      "繞駛興福寮66巷" => "detour via Xingfuliao Ln. 66",
      "不繞駛興福寮66巷" => "skips Xingfuliao Ln. 66",
      "竹林慈玄宮" => "Zhulin Cixuan Temple",
      "繞駛竹林慈玄宮" => "detour via Zhulin Cixuan Temple",
      "不繞駛竹林慈玄宮" => "skips Zhulin Cixuan Temple",
      "竿蓁二街福德宮" => "Qianzhen 2nd St. Fude Temple",
      "繞駛竿蓁二街福德宮" => "detour via Qianzhen 2nd St. Fude Temple",
      "紅樹林路" => "Hongshulin Rd.",
      "繞駛紅樹林路" => "detour via Hongshulin Rd.",
      "八仙樂園" => "Bali Paradise",
      "繞駛八仙樂園" => "detour via Bali Paradise",
      "八里國中" => "Bali Junior High School",
      "繞駛八里國中" => "detour via Bali Junior High School",
      "不繞駛八里國中" => "skips Bali Junior High School",
      "繞駛惠國市場" => "detour via Huiguo Market",
      "單向繞駛" => "outbound detour via Dacheng Rd.",
      "低地板" => "low-floor",
      "非低地板" => "non-low-floor",
      "金瓜石" => "Jinguashi",
      "延駛水湳洞" => "extended to Shuinandong",
      "水湳洞" => "Shuinandong",
      "繞駛水湳洞" => "detour via Shuinandong",
      "繞駛威遠廟" => "detour via Weiyuan Temple",
      "威遠廟" => "Weiyuan Temple",
      "崁腳" => "Kanjiao",
      "北基新城" => "Beiji New Town",
      "圳頭" => "Zuntou",
      "繞駛龜吼漁港" => "detour via Guihou Fishing Harbor",
      "龜吼漁港" => "Guihou Fishing Harbor",
      "延駛耕莘醫院" => "extended to Cardinal Tien Hospital",
      "正線" => "Main Line",
      "延駛馬崗" => "extended to Magang",
      "馬崗" => "Magang",
      "延駛石碇" => "extended to Shiding",
      "石碇" => "Shiding",
      "阿南坑、貴興路" => "Anankeng & Guixing Rd.",
      "繞駛阿南坑、貴興路" => "detour via Anankeng & Guixing Rd.",
      "不繞駛阿南坑、貴興路" => "skips Anankeng & Guixing Rd.",
      "土城醫院" => "Tucheng Hospital",
      "繞駛土城醫院" => "detour via Tucheng Hospital",
      "不繞駛土城醫院" => "skips Tucheng Hospital",
      "不經二甲" => "skips Erjia",
      "二甲" => "Erjia",
      "延駛邱厝巷" => "extended to Qiucuo Lane",
      "邱厝巷" => "Qiucuo Lane",
      "寵物公車" => "Pet Bus",
      "繞駛八勢路" => "detour via Bashi Rd.",
      "八勢路" => "Bashi Rd.",
      "經正德國中" => "via Zhengde Junior High",
      "正德國中" => "Zhengde Junior High",
      "直行中山北路" => "Zhongshan N. Rd. (straight)",
      "中山北路" => "Zhongshan N. Rd.",
      "延駛淡水商工" => "extended to Tamsui Vocational High School",
      "淡水商工" => "Tamsui Vocational High School",
      "繞駛台北灣社區" => "detour via Taipei Bay Community",
      "台北灣社區" => "Taipei Bay Community",
      "台北灣" => "Taipei Bay",
      "繞駛貢寮" => "detour via Gongliao",
      "貢寮" => "Gongliao",
      "貢寮衛生所" => "Gongliao Health Center",
      "十分" => "Shifen",
      "十分寮" => "Shifenliao",
      "平溪" => "Pingxi",
      "新民" => "Xinmin",
      "新春" => "Xinchun",
      "正新民反新春" => "out Xinmin / back Xinchun",
      "正新春反新民" => "out Xinchun / back Xinmin",
      "只到崑崙里" => "to Kunlun Village only",
      "只到捷運大坪林站" => "to MRT Dapinglin Station only",
      "只到新埔站" => "to Xinpu Station only",
      "桃園酒廠發車" => "from Taoyuan Winery",
      "延和路" => "Yanhe Rd.",
      "海山拖吊場" => "Haishan Tow Yard",
      "青潭" => "Qingtan",
      "大崎腳" => "Daqijiao"
    }.freeze

    def self.series_match?(route_name, series:, city: nil)
      return true if series.blank?

      public_ref(route_name, collapse_extra_digits: true, city:).match?(/\A#{Regexp.escape(series.to_s)}\d{2}/) ||
        route_name.to_s.match?(/\A#{Regexp.escape(series.to_s)}\d{2}/)
    end

    def self.test_route_name?(route_name)
      name = route_name.to_s
      name.include?("測試") || name.include?("煙火專車")
    end

    def self.public_ref(route_name, collapse_extra_digits: true, city: nil)
      raw = route_name.to_s.strip
      return raw unless collapse_extra_digits
      # Only Keelung TDX names use extra trailing digits (3014 → 301). Everywhere
      # else keep 5014 / 1717 intact so browse bands stay in 1000+.
      return raw unless city&.id == "Keelung"
      # 17xx–19xx are standalone four-digit routes, not 1xx detours.
      return raw if raw.match?(/\A1[7-9]\d{2}\z/)
      return raw unless (match = raw.match(/\A(\d{3})\d+\z/))

      match[1]
    end

    def self.extra_digit_name?(route_name)
      route_name.to_s.strip.match?(/\A\d{3}\d+\z/)
    end

    # TDX encodes some Keelung detours as extra-digit names (3014, 3063). Prefer the
    # public 3-digit listings when they already distinguish multiple paths; otherwise
    # keep extras that add a new via (and drop extras that only duplicate the parent).
    # Highway coaches keep their full route numbers (e.g. 1820).
    def self.select_listed_routes(routes, collapse_extra_digits: true)
      routes = Array(routes)
      return routes unless collapse_extra_digits

      listed = routes.reject { |route| extra_digit_name?(route_name_zh(route)) }
      extras = routes - listed
      return routes if listed.empty?
      return listed if extras.empty?

      listed_vias = listed.map { |route| variant_label(route).to_s }.uniq
      return listed if listed_vias.size > 1

      listed + extras.reject { |route| listed_vias.include?(variant_label(route).to_s) }
    end

    def self.route_name_zh(route)
      value = route["RouteName"]
      return value.to_s if value.is_a?(String)

      value&.[]("Zh_tw").to_s.presence || value&.[](:Zh_tw).to_s.presence.to_s
    end

    # When one via is a trunk street and the others are place detours (市場 / 新村),
    # treat the street as the unlabeled original route.
    def self.unlabeled_trunk_via(via_labels)
      unique = Array(via_labels).map(&:to_s).uniq
      unique.find { |via| trunk_via?(via, unique - [ via ]) }
    end

    def self.trunk_via?(via, sibling_vias)
      via = via.to_s
      return false if via.blank? || !via.match?(/[路街巷]\z/)

      Array(sibling_vias).none? { |other| other.to_s.match?(/[路街巷]/) }
    end

    def self.variant_label(route)
      headsigns = Array(route["SubRoutes"] || route["SubRoutes"]).filter_map { |sub| sub["Headsign"].to_s.presence }
      vias = headsigns.flat_map { |sign| via_tokens(sign) }.uniq

      if (via = vias.find { |value| value.include?("祥豐") })
        return via.include?("街") ? via : "祥豐街"
      end
      if (via = vias.find { |value| value.include?("中正") })
        return via.include?("路") ? via : "中正路"
      end
      return vias.join("、") if vias.any?

      compact_headsign(headsigns.first)
    end

    def self.via_tokens(sign)
      sign.to_s.scan(/經\s*([^經)）（(]+)/).flatten.flat_map { |chunk|
        chunk.split(/[、，,]/)
      }.map { |token| token.gsub(/[\s()（）]+/, "") }.compact_blank.uniq
    end

    # ActiveSupport parameterize strips Han characters, so 紅32 and 32 both
    # become "32". Map common Taipei/New Taipei tokens before slugifying.
    REF_TOKEN_MAP = {
      "內科" => "neike",
      "專車" => "zhuanche",
      "通勤" => "tongqin",
      "幹線" => "ganxian",
      "先導" => "xiandao",
      "快速" => "kuaisu",
      "跳蛙" => "tiaowa",
      "貓空" => "maokong",
      "市民" => "shimin",
      "紅" => "hong",
      "藍" => "lan",
      "綠" => "lu",
      "棕" => "zong",
      "橘" => "ju",
      "桔" => "ju",
      "黃" => "huang",
      "小" => "xiao",
      "副" => "sub"
    }.freeze

    # Legacy slug tokens: 區 was "qu", 副 was "fu". Keep finders / redirects working.
    def self.modernize_variant_slug(slug)
      text = slug.to_s.dup
      text.gsub!(/_qu(?=_|-|\d|\.|\z)/, "_sh")
      text.gsub!(/_fu(?=_|-|\d|\.|\z)/, "_sub")
      text.gsub!(/-qu(?=_|-|\d|\.|\z)/, "-sh")
      text.gsub!(/-fu(?=_|-|\d|\.|\z)/, "-sub")
      text.gsub!(/(?<=[\dA-Za-z])qu(?=_|-|\d|\.|\z)/, "sh")
      text.gsub!(/(?<=[\dA-Za-z])fu(?=_|-|\d|\.|\z)/, "sub")
      text
    end

    def self.ref_slug(ref)
      raw = ref.to_s.strip
      return "unknown_#{Digest::SHA1.hexdigest("empty")[0, 8]}" if raw.blank?

      labeled = REF_TOKEN_MAP.sort_by { |token, _| -token.length }.reduce(raw.dup) do |text, (zh, en)|
        text.gsub(zh, en)
      end
      # 區 → sh only as the short-turn suffix (311區 / 791區). Do not rewrite
      # mid-name district tokens such as 貢寮區衛生 → …_sh_….
      labeled.gsub!(/(?<=[\dA-Za-z])區/, "sh")

      if labeled.match?(/\p{Han}/)
        base = labeled.gsub(/\p{Han}+/, "_").parameterize(separator: "_").presence
        digest = Digest::SHA1.hexdigest(raw)[0, 10]
        return [ base, digest ].compact_blank.join("_")
      end

      labeled.parameterize(separator: "_").presence || Digest::SHA1.hexdigest(raw)[0, 10]
    end

    def self.variant_slug(via)
      return if via.blank?
      return "xiangfeng" if via.include?("祥豐")
      return "zhongzheng" if via.include?("中正")

      latin = via.parameterize(separator: "_").presence
      return latin if latin.present?

      Digest::SHA1.hexdigest(via)[0, 10]
    end

    def self.variant_label_en(via)
      text = via.to_s
      return VIA_EN[text] if VIA_EN.key?(text)

      if (match = text.match(/(\d{2}:\d{2})前、(\d{2}:\d{2})後不繞駛三總\z/))
        timed = "before #{match[1]} and after #{match[2]}, skips Tri-Service General Hospital"
        prefix = text.delete_suffix(match[0]).sub(/、\z/, "")
        return timed if prefix.empty?

        return "#{variant_label_en(prefix)}, #{timed}"
      end

      text.split("、").map { |part|
        VIA_EN[part] || VIA_EN.find { |zh, _en| part.include?(zh) }&.last || part
      }.join(", ")
    end

    def self.compact_headsign(sign)
      return if sign.blank?

      text = sign.to_s.gsub(/[→←—–\-／\/]+/, " ").squeeze(" ").strip
      parts = text.split(/\s+/).reject { |part| part.match?(/車站|火車站|總站/) }
      parts.first.presence || text.presence
    end

    def self.parse_wkt_lines(wkt)
      return [] if wkt.blank?
      return geojson_lines(wkt) if wkt.is_a?(Hash)

      text = wkt.to_s.strip
      if text.upcase.start_with?("MULTILINESTRING")
        inner = text.sub(/\AMULTILINESTRING\s*/i, "")
        split_line_groups(inner).filter_map { |group| parse_coordinate_list(group) }
      elsif text.upcase.start_with?("LINESTRING")
        coords = parse_coordinate_list(text.sub(/\ALINESTRING\s*/i, ""))
        coords ? [ coords ] : []
      else
        []
      end
    end

    def self.geojson_lines(geometry)
      type = geometry["type"] || geometry[:type]
      coordinates = geometry["coordinates"] || geometry[:coordinates]
      case type
      when "LineString" then [ coordinates ]
      when "MultiLineString" then Array(coordinates)
      else []
      end
    end

    def self.split_line_groups(wkt_inner)
      groups = []
      depth = 0
      start = nil
      wkt_inner.each_char.with_index do |char, index|
        if char == "("
          start = index + 1 if depth.zero?
          depth += 1
        elsif char == ")"
          depth -= 1
          groups << wkt_inner[start...index] if depth.zero? && start
        end
      end
      groups
    end

    def self.parse_coordinate_list(text)
      pairs = text.to_s.scan(/(-?\d+(?:\.\d+)?)\s+(-?\d+(?:\.\d+)?)/)
      return nil if pairs.length < 2

      pairs.map { |lon, lat| [ lon.to_f, lat.to_f ] }
    end

    private_class_method :geojson_lines, :split_line_groups, :parse_coordinate_list

    private

    def build_collection(route, shapes, stop_of_routes, distinguish_via: false, unlabeled_via: nil)
      trunk = self.class.trunk_label(zh_name(route["RouteName"]))
      ref = trunk&.dig(:ref) || route_ref(route)
      via = if trunk
        nil
      else
        variant_via(route, distinguish_via:, unlabeled_via:) || intercity_detour_via(route) ||
          route["_import_detour"].presence || route["_import_main_label"]
      end
      slug = route_slug(route, distinguish_via:, unlabeled_via:)
      operators = self.class.operators_for_route(route)
      operator = operators.first || {}
      color = Geojson::BusOperatorColors.for_route(ref: ref, name: operator[:name], id: operator[:id]) ||
        route_color(operator[:name].presence || operator[:id].presence || slug)
      official_map_url = official_map_url_for(route)

      if @city.kind != :intercity || route["_import_blank_sub"] || route["_import_detour"]
        shapes, stop_of_routes = primary_subroute_rows(Array(shapes), Array(stop_of_routes), name: zh_name(route["RouteName"]))
      end

      # Circular routes (593/594/595): both ends share a stop, so the board
      # headsign is "{ref}-{destination}" (593-沙崙), not a bare number.
      # Path-pair vias (595 新民／新春) append as 595-淡海新市鎮（新民）.
      board = circular_board_name(ref, route, stop_of_routes)
      name = trunk&.dig(:name) || named_with_via(board, ref, via) || display_name(ref, via)
      name_en = trunk&.dig(:name_en) ||
        named_with_via_en(circular_board_name_en(ref, route, stop_of_routes), ref, via) ||
        Geojson::BusNamesEn.name_en(display_name_en(ref, via), ref: ref, city_id: @city.id)

      # shapes / stop_of_routes are already scoped to this RouteUID by the caller.
      line_features = Array(shapes).filter_map do |shape|
        lines = self.class.parse_wkt_lines(shape["Geometry"] || shape["geometry"])
        next if lines.empty?

        coordinates = Geojson::BusLoopCloser.merge_line_strings(lines)
        next if coordinates.length < 2

        loop_stops = loop_stops_for_shape?(Array(stop_of_routes), shape["Direction"])
        coordinates = Geojson::BusShapeSharpener.sharpen(coordinates)
        unless loop_stops
          opposite_direction = Array(stop_of_routes).map { |row| row["Direction"] }.uniq
            .find { |value| value.to_s != shape["Direction"].to_s }
          coordinates = Geojson::BusShapeTrimmer.trim_to_stops(
            coordinates,
            stop_points_for_direction(Array(stop_of_routes), shape["Direction"]),
            end_point: stop_points_for_direction(Array(stop_of_routes), opposite_direction).first
          )
          # Shared blank-UID shapes (542 本線 / 延駛) and short-turn detours
          # need an explicit clip to the variant's first / last stop.
          if route["_import_detour"] || route["_import_blank_sub"]
            coordinates = clip_to_terminals(coordinates, stop_points_for_direction(Array(stop_of_routes), shape["Direction"]))
          end
        end
        coordinates = Geojson::BusLoopCloser.close_loop_coordinates(coordinates, force: loop_stops)

        properties = {
          feature_type: "route",
          ref: ref,
          name: name,
          name_en: name_en,
          color: color,
          direction: shape["Direction"]
        }
        properties[:loop] = true if loop_stops || Geojson::BusLoopCloser.nearly_closed?(coordinates)

        {
          type: "Feature",
          properties: properties,
          geometry: {
            type: "LineString",
            coordinates: coordinates
          }
        }
      end

      return nil if line_features.empty?

      line_features = snap_corridor_line_features(line_features)
      if line_features.length == 2
        joined = Geojson::BusShapeTrimmer.join_termini(*line_features.map { |feature| feature.dig(:geometry, :coordinates) })
        line_features.zip(joined).each { |feature, coords| feature[:geometry][:coordinates] = coords }
      end
      station_features = station_features_for(Array(stop_of_routes), name: name, color: color)

      properties = {
        id: slug,
        name: name,
        name_en: name_en,
        ref: ref,
        color: color,
        city_id: @city.id,
        source: "TDX Bus Shape / StopOfRoute"
      }
      properties[:loop] = true if line_features.any? { |feature| feature.dig(:properties, :loop) || feature.dig("properties", "loop") }
      if via.present?
        properties[:via] = via
        properties[:via_en] = VIA_EN[via] || Geojson::BusNamesEn.translate(via)
      end
      # 903 / 521 / 藍20: 經三總 stays the plain ref; 不經三總 is the labelled skip.
      if via.to_s == "不繞駛三總"
        properties[:campus_span] = "outside"
      elsif route["_import_blank_sub"] && hospital_skip_split?(route)
        properties[:campus_span] = "inside"
      end
      if (note = self.class.service_note_for(ref, route: route))
        properties[:service_note] = note["zh"]
        properties[:service_note_en] = note["en"]
      end
      tdx_ref = route["_import_tdx_ref"].presence || trunk&.dig(:tdx_ref)
      properties[:tdx_ref] = tdx_ref if tdx_ref
      properties[:official_map_url] = official_map_url if official_map_url.present?
      # Prefer outbound StopOfRoute pole names (樹林藝文綜合行政大樓) over the
      # abbreviated Route 起迄站名 (樹林). Circular boards still need the Route
      # destination (593-沙崙) when both ends share a stop.
      apply_termini!(properties, route, station_features)
      unless keelung?
        properties[:operator_id] = operator[:id] if operator[:id].present?
        properties[:operator] = operator[:name] if operator[:name].present?
        operator_en = operator[:name_en].presence || Geojson::BusNamesEn.operator_en(operator[:name])
        properties[:operator_en] = operator_en if operator_en.present?
        if operators.size == 2 && (partner = operators[1])
          properties[:operator_id_2] = partner[:id] if partner[:id].present?
          properties[:operator_2] = partner[:name] if partner[:name].present?
          partner_en = partner[:name_en].presence || Geojson::BusNamesEn.operator_en(partner[:name])
          properties[:operator_2_en] = partner_en if partner_en.present?
          if (color_2 = Geojson::BusOperatorColors.second_color(operator[:name], partner[:name], ref: ref))
            properties[:color_2] = color_2
          end
        end
      end

      {
        id: slug,
        type: "FeatureCollection",
        name: name,
        properties: properties,
        features: line_features + station_features
      }
    end

    # A split variant still spans several SubRoutes (short turns, extensions,
    # duplicate shapes without a SubRouteUID). Draw one path per direction: the
    # SubRoute with the most stops, with its own shape or the best-fitting one.
    def primary_subroute_rows(shapes, stop_of_routes, name: nil)
      shape_km = shapes.to_h { |shape|
        line = Geojson::BusLoopCloser.merge_line_strings(self.class.parse_wkt_lines(shape["Geometry"] || shape["geometry"]))
        [ [ shape["SubRouteUID"].to_s, shape["Direction"].to_s ], Geojson::BusShapeTrimmer.path_length(line) ]
      }
      stop_rows = stop_of_routes.group_by { |row| row["Direction"].to_s }.values.map { |rows|
        exact = rows.select { |row| name.present? && zh_name(row["SubRouteName"]).to_s.strip == name.strip }
        (exact.presence || rows).max_by { |row|
          [ Array(row["Stops"]).length, shape_km[[ row["SubRouteUID"].to_s, row["Direction"].to_s ]] || 0 ]
        }
      }
      shape_rows = shapes.group_by { |shape| shape["Direction"].to_s }.map { |direction, rows|
        primary = stop_rows.find { |row| row["Direction"].to_s == direction }
        next rows.first unless primary

        own = rows.find { |shape| shape["SubRouteUID"].to_s.present? && shape["SubRouteUID"].to_s == primary["SubRouteUID"].to_s }
        own || rows.min_by { |shape| shape_stop_misfit(shape, primary) }
      }
      [ shape_rows, stop_rows ]
    end

    TERMINAL_OVERSHOOT_METERS = 300
    TERMINAL_SNAP_METERS = 150

    # A short-turn variant can borrow the full route's shape; cut whatever
    # runs past its first / last stop.
    def clip_to_terminals(line, stops)
      return line if line.length < 3 || stops.length < 2

      nearest = ->(point, range) {
        range.min_by { |index| Geojson::BusLoopCloser.meters_between(line[index], point) }
      }
      half = line.length / 2
      if Geojson::BusLoopCloser.meters_between(line.last, stops.last) > TERMINAL_OVERSHOOT_METERS
        index = nearest.(stops.last, half...line.length)
        line = line[0..index] if Geojson::BusLoopCloser.meters_between(line[index], stops.last) <= TERMINAL_SNAP_METERS
      end
      if Geojson::BusLoopCloser.meters_between(line.first, stops.first) > TERMINAL_OVERSHOOT_METERS
        index = nearest.(stops.first, 0...[ half, line.length - 2 ].min)
        line = line[index..] if Geojson::BusLoopCloser.meters_between(line[index], stops.first) <= TERMINAL_SNAP_METERS
      end
      line
    end

    def shape_stop_misfit(shape, stop_row)
      line = Geojson::BusLoopCloser.merge_line_strings(self.class.parse_wkt_lines(shape["Geometry"] || shape["geometry"]))
      return Float::INFINITY if line.length < 2

      stops = stop_points_for_direction([ stop_row ], stop_row["Direction"])
      return Float::INFINITY if stops.empty?

      distances = stops.map { |stop|
        line.each_cons(2).map { |a, b| Geojson::BusShapeTrimmer.project(stop, a, b)[:distance] }.min
      }
      misfit = distances.sum / distances.length
      misfit + (Geojson::BusShapeTrimmer.path_length(line) / 1_000_000.0)
    end

    def merge_collections(collections, slug)
      first = collections.first
      features = collections.flat_map { |collection| collection[:features] }
      seen_stops = {}
      merged_features = features.select do |feature|
        next true unless feature.dig(:properties, :feature_type) == "station"

        key = "#{feature.dig(:properties, :ref)}:#{feature.dig(:properties, :direction)}"
        next false if seen_stops[key]

        seen_stops[key] = true
      end

      first.merge(id: slug, features: snap_corridor_line_features(merged_features))
    end

    def snap_corridor_line_features(features)
      # Previously dropped inbound vertices within 50m of outbound so shared
      # corridors were drawn once. That left inbound as disconnected spur stubs
      # at junctions ("斷在路口"). Direction banding now separates outbound /
      # inbound on screen, so keep both full polylines.
      features
    end

    def loop_stops_for_shape?(stop_of_routes, direction)
      rows = Array(stop_of_routes).select { |row| row["Direction"].to_s == direction.to_s }
      rows = Array(stop_of_routes) if rows.empty?
      stops = rows.flat_map { |row| Array(row["Stops"]) }
      return false if stops.length < 2

      first = stop_identity(stops.first)
      last = stop_identity(stops.last)
      first.present? && first == last
    end

    def stop_points_for_direction(stop_of_routes, direction)
      rows = stop_of_routes.select { |row| row["Direction"].to_s == direction.to_s }
      rows.flat_map { |row| Array(row["Stops"]) }.filter_map do |stop|
        position = stop["StopPosition"] || {}
        lon = position["PositionLon"] || position["lon"]
        lat = position["PositionLat"] || position["lat"]
        [ lon.to_f, lat.to_f ] if lon.present? && lat.present?
      end
    end

    def stop_identity(stop)
      stop["StopUID"].to_s.presence ||
        stop["StopID"].to_s.presence ||
        zh_name(stop["StopName"]).presence
    end

    def apply_termini!(properties, route, station_features)
      by_direction = Array(station_features).group_by { |feature|
        feature.dig(:properties, :direction).to_s.presence || feature.dig("properties", "direction").to_s
      }
      outbound = by_direction["0"].presence || by_direction["1"]
      first = outbound&.first&.dig(:properties) || outbound&.first&.dig("properties") || {}
      last = outbound&.last&.dig(:properties) || outbound&.last&.dig("properties") || {}
      from = first[:name].presence || first["name"].presence
      to = last[:name].presence || last["name"].presence

      if from.present? && to.present? && from != to
        properties[:departure] = from
        properties[:departure_en] = first[:name_en].presence || first["name_en"]
        properties[:destination] = to
        properties[:destination_en] = last[:name_en].presence || last["name_en"]
        return
      end

      if (departure = route["DepartureStopNameZh"].presence)
        properties[:departure] = departure
        properties[:departure_en] = route["DepartureStopNameEn"].presence
      end
      if (destination = route["DestinationStopNameZh"].presence)
        properties[:destination] = destination
        properties[:destination_en] = route["DestinationStopNameEn"].presence
      end
    end

    def station_features_for(stop_rows, name:, color:)
      seen = {}

      stop_rows.flat_map do |row|
        direction = row["Direction"]
        Array(row["Stops"]).map { |stop| [ stop, direction ] }
      end.filter_map do |stop, direction|
        uid = stop["StopUID"].to_s.presence || stop["StopID"].to_s
        key = "#{uid}:#{direction}"
        next if uid.blank? || seen[key]

        position = stop["StopPosition"] || {}
        lon = position["PositionLon"] || position["lon"]
        lat = position["PositionLat"] || position["lat"]
        next if lon.blank? || lat.blank?

        seen[key] = true
        stop_name = zh_name(stop["StopName"]).presence || uid
        properties = {
          feature_type: "station",
          ref: uid,
          name: stop_name,
          name_en: en_name(stop["StopName"]).presence,
          line: name,
          color: color
        }
        properties[:direction] = direction unless direction.nil?
        station_id = stop["StationID"].to_s.presence || stop["StationUID"].to_s.presence
        properties[:station_id] = station_id if station_id.present?
        properties[:stop_role] = "depot" if self.class.depot_stop_name?(stop_name)

        {
          type: "Feature",
          properties: properties,
          geometry: { type: "Point", coordinates: [ lon.to_f, lat.to_f ] }
        }
      end
    end

    # Bus dispatch yards / operator terminals that appear as StopOfRoute poles.
    # Never treat rail/metro 「機廠」 passenger-stop names as bus dispatch sites.
    def self.depot_stop_name?(name)
      text = name.to_s
      return false if text.blank?
      return false if text.match?(/立體停車場|公有市場|公有停車場|寺停車場|博物館|藝文園區|花鐘|林務局|招呼站/)
      return false if rail_or_metro_yard_stop_name?(text)

      text.include?("調度站") ||
        text.include?("調度場") ||
        text.match?(/客運.{0,24}停車場/) ||
        text.match?(/客運.{0,24}車場/) ||
        text.match?(/客運.{0,24}場站/) ||
        text.match?(/(?:\A|[\(（])調度/) ||
        text.match?(/調車場\z/) ||
        bus_operator_station_name?(text) ||
        bus_terminal_name?(text) ||
        bus_substation_name?(text)
    end

    def self.rail_or_metro_yard_stop_name?(name)
      text = name.to_s
      text.include?("機廠") || text.match?(/高鐵總/)
    end

    def self.bus_terminal_name?(name)
      text = name.to_s
      return false if text.blank? || text == "總站"
      return false if text.match?(/捷運|輕軌|高鐵/)

      text.include?("總站")
    end

    def self.bus_substation_name?(name)
      text = name.to_s
      return false if text.blank? || text.match?(/林務/)

      text.include?("分站")
    end

    def self.bus_operator_station_name?(name)
      text = name.to_s
      text.include?("客運站") || text.match?(/客運.{0,20}站\z/)
    end

    def write_collection!(collection)
      slug = collection.delete(:id)
      ref = collection.dig(:properties, :ref)
      path = Geojson::BusLayout.geojson_path(
        city_id: @city.id,
        slug:,
        ref:,
        operator_id: collection.dig(:properties, :operator_id),
        operator_name: collection.dig(:properties, :operator)
      )
      collection = collection.deep_stringify_keys
      Geojson::BusTerminalAccess.process_collection!(collection)
      Geojson::BusShapePatches.process_collection!(collection)
      Geojson::BusRoundabouts.process_collection!(collection)
      Geojson::BusRoadSnapper.process_collection!(collection)
      Geojson::BusTerminusHandoff.process_collection!(collection)
      Geojson::BusCornerRounder.process_collection!(collection)
      # Anchors for a chord are easier to see after roundabout densify.
      Geojson::BusShapePatches.process_collection!(collection)
      if path.exist?
        previous = JSON.parse(path.read)["properties"] || {}
        %w[merged_refs off_days service_window].each do |key|
          collection["properties"][key] = previous[key] if previous[key].present?
        end
      end
      FileUtils.mkdir_p(path.dirname)
      File.write(path, "#{JSON.pretty_generate(collection)}\n")
      puts "Wrote #{path}"
    end

    def route_slug(route, distinguish_via: false, unlabeled_via: nil)
      self.class.slug_for(route, city: @city, distinguish_via:, unlabeled_via:)
    end

    def variant_via(route, distinguish_via:, unlabeled_via: nil)
      return nil unless distinguish_via

      via = self.class.variant_label(route).presence || "其他"
      return nil if unlabeled_via.present? && via == unlabeled_via

      via
    end

    # True when this blank-sub main line was split off a 不經三總 SubRoute.
    def hospital_skip_split?(route)
      self.class.hospital_skip_split_route?(route)
    end

    def route_ref(route)
      return route["_import_ref"].to_s if route["_import_ref"].present?

      self.class.public_ref(
        zh_name(route["RouteName"]).presence || route["RouteID"].to_s,
        collapse_extra_digits: @city.kind != :intercity,
        city: @city
      )
    end

    def display_name(ref, via)
      return ref if via.blank?

      label = via.to_s.sub(/\A經/, "")
      return "#{ref}（#{label}）" if @city.kind == :intercity || label.match?(NAMED_LABEL_PATTERN)

      "#{ref}（經#{label}）"
    end

    def circular_board_name(ref, route, stop_of_routes)
      dest = route["DestinationStopNameZh"].to_s.presence
      dep = route["DepartureStopNameZh"].to_s.presence
      return unless dest && dep && dest != dep
      return unless circular_stop_list?(stop_of_routes)

      "#{ref}-#{dest}"
    end

    def circular_board_name_en(ref, route, stop_of_routes)
      return unless circular_board_name(ref, route, stop_of_routes)

      dest = route["DestinationStopNameZh"].to_s
      dest_en = route["DestinationStopNameEn"].presence || Geojson::BusNamesEn.translate(dest)
      "#{ref}-#{dest_en}"
    end

    def named_with_via(base, ref, via)
      return if base.blank? && via.blank?
      return base if via.blank?
      return display_name(ref, via) if base.blank?

      label = via.to_s.sub(/\A經/, "")
      "#{base}（#{label}）"
    end

    def named_with_via_en(base, ref, via)
      return if base.blank? && via.blank?
      return base if via.blank?
      return Geojson::BusNamesEn.name_en(display_name_en(ref, via), ref: ref, city_id: @city.id) if base.blank?

      label = self.class.variant_label_en(via.to_s.sub(/\A經/, ""))
      "#{base} (#{label})"
    end

    # A direction is circular when its own stop list starts and ends on the same
    # name (UIDs often differ for the two poles). Joining 去+返 would make every
    # out-and-back look circular, including 596's 崑崙里 short turn.
    def circular_stop_list?(stop_of_routes)
      rows = Array(stop_of_routes).select { |row| Array(row["Stops"]).length >= 2 }
      return false if rows.empty?

      rows.all? do |row|
        stops = row["Stops"]
        first = zh_name(stops.first["StopName"]).presence
        last = zh_name(stops.last["StopName"]).presence
        first.present? && first == last
      end
    end

    def display_name_en(ref, via)
      return ref if via.blank?
      return "#{ref} (#{VIA_EN[via]})" if VIA_EN.key?(via)

      if (detour = via.to_s[/\A(?:繞駛|繞經)(.+)\z/, 1])
        return "#{ref} (detour via #{self.class.variant_label_en(detour)})"
      end

      label = self.class.variant_label_en(via)
      return "#{ref} (#{label})" if @city.kind == :intercity || via.to_s.match?(NAMED_LABEL_PATTERN)

      "#{ref} (via #{label})"
    end

    def route_label(route)
      "#{route['RouteUID']} #{route_ref(route)}".strip
    end

    def route_color(seed)
      index = Digest::SHA1.hexdigest(seed.to_s)[0, 8].to_i(16)
      PALETTE[index % PALETTE.length]
    end

    def official_map_url_for(route)
      explicit = route["RouteMapImageUrl"].to_s.presence || route["RouteMapUrl"].to_s.presence
      if explicit.present?
        # TDX often gives HTML portal pages (ebus MapOverview); resolve to a direct image for <img>.
        resolved = Geojson::BusOfficialMapFetcher.new(
          city_ids: [ @city.id ],
          resolve_portals: false,
          rewrite_manifest: false,
          sync_tdx: false
        ).resolve_direct_image_url(explicit)
        return resolved if resolved.present?
        return nil if Geojson::BusOfficialMapFetcher::PORTAL_HINT.match?(explicit)

        return explicit
      end

      intercity_schematic_url(route)
    end

    def intercity_schematic_url(route)
      return unless @city.kind == :intercity

      ref = route_ref(route).to_s
      base = ref.sub(/[A-J]\z/i, "")
      return if base.blank?

      "https://web.taiwanbus.tw/MISUploadData/Schematic/file/#{base}.jpg"
    end

    def filter_variant_rows(rows, route)
      uids = Array(route["_import_sub_uids"]).map(&:to_s).reject(&:blank?)
      return rows if uids.empty? && !route["_import_blank_sub"]

      kept = rows.select { |row|
        uid = row["SubRouteUID"].to_s
        uids.include?(uid) || (route["_import_blank_sub"] && uid.blank?)
      }
      return kept unless route["_import_detour"]

      # Detour shapes may only be published without a SubRouteUID. That is
      # only safe when the other SubRoutes carry their own shapes; otherwise
      # the blank shapes are the plain route.
      others = rows.any? { |row| row["SubRouteUID"].to_s.present? && !uids.include?(row["SubRouteUID"].to_s) }
      if others
        covered = kept.map { |row| row["Direction"].to_s }
        return kept + rows.select { |row| row["SubRouteUID"].to_s.blank? && !covered.include?(row["Direction"].to_s) }
      end

      # Shared blank-UID geometry (e.g. 542): both 本線 and 延駛 clip the same
      # line to their own StopOfRoute terminals.
      return kept if kept.any?

      rows.select { |row| row["SubRouteUID"].to_s.blank? }
    end

    # e.g. "臺北→竹東[繞駛關西市區]" → "繞駛關西市區"
    def intercity_detour_via(route)
      return unless @city.kind == :intercity

      headsign = route["_import_headsign"].to_s
      return if headsign.blank?

      if (match = headsign.match(/\[([^\]]+)\]/))
        return match[1].strip
      end

      tokens = self.class.via_tokens(headsign)
      tokens.join("、").presence
    end

    def prune_stale_city_files!(kept_slugs)
      city_key = @city.id.underscore
      sibling_prefixes = Geojson::BusCatalog.cities
        .map { |entry| entry.id.underscore }
        .reject { |key| key == city_key }
        .select { |key| key.start_with?("#{city_key}_") }
      prefix = "#{city_key}_"
      search_roots = [ Geojson::BusLayout.bus_root ]
      subdir = Geojson::BusLayout.subdir_for(@city.id)
      search_roots << Geojson::BusLayout.bus_root.join(subdir) if subdir.present?

      search_roots.each do |root|
        next unless root.exist?

        Dir.glob(root.join("**/*.geojson")).each do |path|
          slug = File.basename(path, ".geojson")
          next unless slug == city_key || slug.start_with?(prefix)
          next if sibling_prefixes.any? { |sibling| slug == sibling || slug.start_with?("#{sibling}_") }
          next if kept_slugs.include?(slug)

          File.delete(path)
        end
      end
    end

    def keelung?
      @city.id == "Keelung"
    end

    def operator_for(route)
      self.class.operators_for_route(route).first || { id: nil, name: nil, name_en: nil }
    end

    # Operators that actually run this drawn variant. A subroute split that
    # names one company (306(大都會)) keeps that company. Two companies on the
    # same subroutes are a joint operation.
    def self.operators_for_route(route)
      rows = Array(route["Operators"]).filter_map { |row| normalize_operator(row) }.uniq { |row| row[:id].presence || row[:name] }
      pinned = subroute_split(route["_import_detour"])&.last&.dig(:operator_id).to_s
      if pinned.present?
        match = rows.find { |row| row[:id] == pinned }
        return [ match ].compact.presence || rows.take(1)
      end

      parent = route_name_zh(route).strip
      tagged = rows.select { |row|
        variant_subroutes(route).any? { |sub| operator_tagged?(parent, subroute_name_zh(sub), row[:name]) }
      }
      return tagged if tagged.size == 1

      rows
    end

    def self.variant_subroutes(route)
      subs = Array(route["SubRoutes"])
      uids = Array(route["_import_sub_uids"]).map(&:to_s).reject(&:blank?)
      return subs if uids.empty?

      picked = subs.select { |sub| uids.include?(sub["SubRouteUID"].to_s) }
      picked.presence || subs
    end

    def self.operator_tagged?(route_name, subroute_name, operator_name)
      short = operator_name.to_s.sub(/(客運|巴士|汽車|通運|小巴)\z/, "")
      return false if short.length < 2

      tags = [ short ]
      tags << "北客" if short == "臺北" || short == "台北"
      rest = subroute_name.to_s.delete_prefix(route_name.to_s)
      tags.any? { |tag| rest.match?(/(?:\A|[()（）])#{Regexp.escape(tag)}(?:\z|[()（）])/) }
    end

    def self.subroute_name_zh(sub)
      route_name_zh("RouteName" => sub["SubRouteName"]).strip
    end

    def self.normalize_operator(row)
      return unless row.is_a?(Hash)

      name = route_name_zh("RouteName" => row["OperatorName"]).sub(/股份有限公司\z/, "").strip
      name = row["OperatorID"].to_s if name.blank?
      return if name.blank?

      {
        id: row["OperatorID"].to_s.presence,
        name: name,
        name_en: row.dig("OperatorName", "En").to_s.presence || row.dig("OperatorName", :En).to_s.presence
      }
    end

    def zh_name(value)
      return value.to_s if value.is_a?(String)

      value&.[]("Zh_tw").to_s.presence || value&.[](:Zh_tw).to_s.presence
    end

    def en_name(value)
      return nil if value.is_a?(String)

      value&.[]("En").to_s.presence || value&.[](:En).to_s.presence
    end
  end
end
