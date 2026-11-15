# frozen_string_literal: true

require "digest"

module Geojson
  module BusCatalog
    City = Data.define(:id, :tdx_city, :kind)

    # TDX city codes for /v2/Bus/*/City/{City}. Intercity (公路客運) uses
    # /v2/Bus/*/InterCity instead of a city path.
    CITIES = [
      City.new(id: "Keelung", tdx_city: "Keelung", kind: :city),
      City.new(id: "Taipei", tdx_city: "Taipei", kind: :city),
      City.new(id: "NewTaipei", tdx_city: "NewTaipei", kind: :city),
      City.new(id: "Taoyuan", tdx_city: "Taoyuan", kind: :city),
      City.new(id: "Hsinchu", tdx_city: "Hsinchu", kind: :city),
      City.new(id: "HsinchuCounty", tdx_city: "HsinchuCounty", kind: :city),
      City.new(id: "MiaoliCounty", tdx_city: "MiaoliCounty", kind: :city),
      City.new(id: "Taichung", tdx_city: "Taichung", kind: :city),
      City.new(id: "ChanghuaCounty", tdx_city: "ChanghuaCounty", kind: :city),
      City.new(id: "NantouCounty", tdx_city: "NantouCounty", kind: :city),
      City.new(id: "YunlinCounty", tdx_city: "YunlinCounty", kind: :city),
      City.new(id: "Chiayi", tdx_city: "Chiayi", kind: :city),
      City.new(id: "ChiayiCounty", tdx_city: "ChiayiCounty", kind: :city),
      City.new(id: "Tainan", tdx_city: "Tainan", kind: :city),
      City.new(id: "Kaohsiung", tdx_city: "Kaohsiung", kind: :city),
      City.new(id: "PingtungCounty", tdx_city: "PingtungCounty", kind: :city),
      City.new(id: "YilanCounty", tdx_city: "YilanCounty", kind: :city),
      City.new(id: "HualienCounty", tdx_city: "HualienCounty", kind: :city),
      City.new(id: "TaitungCounty", tdx_city: "TaitungCounty", kind: :city),
      City.new(id: "PenghuCounty", tdx_city: "PenghuCounty", kind: :city),
      City.new(id: "KinmenCounty", tdx_city: "KinmenCounty", kind: :city),
      # LienchiangCounty (馬祖) omitted: no usable official route maps;
      # TDX shapes are also sparse/unusable on the map.
      City.new(id: "InterCity", tdx_city: nil, kind: :intercity)
    ].freeze

    GREATER_TAIPEI_CITY_IDS = %w[Taipei NewTaipei].freeze
    OTHER_BAND = :other

    # Taoyuan Metro feeders. The city's 紅線／綠線／黃線 are ordinary named routes.
    # Published refs are BR, GR, and GR2; GR1 is accepted for the same green feeder.
    TAOYUAN_METRO_FEEDER = /\A(?:BR|GR\d*)\z/
    TAOYUAN_LOOP = /\A(?:NL|SL)\z/
    TAOYUAN_COLOR_LINE = /\A[紅綠黃]線\z/
    # Numbered 1–100 are trunk buses. Suffixes inherit the base name; 13A is a
    # separate route (南竹－開南大學) and does not carry 龍壽南竹幹線.
    TAOYUAN_TRUNK_NAMES = {
      "1" => "台一幹線",
      "11" => "中山長興幹線",
      "12" => "大湳長庚幹線",
      "13" => "龍壽南竹幹線",
      "15" => "中園大竹幹線",
      "16" => "大龍竹幹線"
    }.freeze
    TAOYUAN_TRUNK_NAME_EXCEPTIONS = %w[13A].freeze
    # 501–506 only. 5010 and the rest of the 5xxx coaches stay in 1000+.
    TAOYUAN_TOURIST = /\A50[1-6](?!\d)/

    # Color-coded MRT feeder routes (捷運接駁五色 / 高雄等彩線).
    COLOR_PREFIX_BANDS = {
      "紅" => :color_hong,
      "藍" => :color_lan,
      "綠" => :color_lu,
      "棕" => :color_zong,
      "橘" => :color_ju,
      "黃" => :color_huang
    }.freeze

    # Thematic bands after pure numeric hundreds (0–99, 100–199, …).
    SPECIAL_BAND_ORDER = [
      :keelung_tr,
      :taoyuan_trunk,
      :taoyuan_tourist,
      :metro_feeder,
      :loop_line,
      :taoyuan_free,
      :taoyuan_xingfu,
      :color_hong,
      :color_lan,
      :color_lu,
      :color_zong,
      :color_ju,
      :color_huang,
      :xiao,
      :ankeng,
      :f_series,
      :neike,
      :taipei_tourist,
      :nangang_soft,
      :commuter,
      :trunk,
      :civic_minibus,
      :maokong,
      :beishi,
      :huaien,
      :named_line,
      :leapfrog,
      OTHER_BAND
    ].freeze

    module_function

    def cities
      CITIES
    end

    def find(id)
      CITIES.find { |city| city.id == id.to_s }
    end

    def greater_taipei_city?(city_id)
      GREATER_TAIPEI_CITY_IDS.include?(city_id.to_s)
    end

    def sidebar_cities
      CITIES.reject { |city| greater_taipei_city?(city.id) }
    end

    def operators_by_city(routes)
      grouped = Hash.new { |hash, key| hash[key] = {} }

      Array(routes).each do |route|
        city_id = route["city_id"].to_s
        next if city_id.empty?

        [
          [ route["operator_id"], route["operator"], route["operator_en"] ],
          [ route["operator_id_2"], route["operator_2"], route["operator_2_en"] ]
        ].each do |operator_id, name, name_en|
          operator_id = operator_id.to_s
          next if operator_id.empty?

          grouped[city_id][operator_id] ||= {
            "id" => operator_id,
            "name" => name.to_s.presence || operator_id,
            "name_en" => name_en.to_s.presence
          }
        end
      end

      grouped.transform_values do |operators|
        operators.values.sort_by { |operator| operator["name"].to_s }
      end
    end

    # Only highway coaches fold by operator; every city bus uses route-number / theme bands.
    def fold_by_operator?(city_id, _routes = nil)
      find(city_id)&.kind == :intercity
    end

    def routes_for(routes, city_id: nil, city_ids: nil, operator_id: nil, operator_ids: nil)
      city_allow = Array(city_ids.presence || city_id).map(&:to_s)
      operator_allow = Array(operator_ids.presence || operator_id).map(&:to_s).reject(&:blank?)

      Array(routes).select do |route|
        next false if city_allow.any? && !city_allow.include?(route["city_id"].to_s)
        next true if operator_allow.empty?

        operator_allow.include?(route["operator_id"].to_s) || operator_allow.include?(route["operator_id_2"].to_s)
      end
    end

    def greater_taipei_routes(routes)
      routes_for(routes, city_ids: GREATER_TAIPEI_CITY_IDS)
    end

    def fold_by_hundreds?(city_id)
      return true if city_id.to_s == "GreaterTaipei"

      find(city_id)&.kind == :city
    end

    def route_number(ref)
      ref.to_s[/\d+/]&.to_i
    end

    def hundreds_band(ref)
      number = route_number(ref)
      return nil if number.nil?
      # 1717 / 5014 stay in 1000+ — do not truncate to 171 → 100–199.
      return 1000 if number >= 1000

      (number / 100) * 100
    end

    # Sidebar band for a public route ref: integer hundreds, or a thematic Symbol.
    def browse_band(ref, city_id: nil)
      text = ref.to_s.strip
      return OTHER_BAND if text.empty?

      # Keelung tourist / shuttle letters sit in the old 0–99 bucket as “T, R”.
      if city_id.to_s == "Keelung" && text.match?(/\A[RT]/i)
        return :keelung_tr
      end

      if city_id.to_s == "Taoyuan" && text.match?(TAOYUAN_METRO_FEEDER)
        return :metro_feeder
      end

      return :loop_line if city_id.to_s == "Taoyuan" && text.match?(TAOYUAN_LOOP)

      unless city_id.to_s == "Taoyuan" && text.match?(TAOYUAN_COLOR_LINE)
        COLOR_PREFIX_BANDS.each do |prefix, band|
          return band if text.start_with?(prefix)
        end
      end

      return :xiao if text.match?(/\A小\d/)
      return :ankeng if text.start_with?("安坑")
      return :f_series if text.match?(/\AF\d/i)
      return :nangang_soft if text.include?("南軟")
      return :neike if text.include?("內科快線") || text.include?("內科通勤")
      return :taipei_tourist if text.match?(/臺?北觀光巴士/)
      return :commuter if text.match?(/\A通勤/) || text.include?("雙園巴士")
      return :civic_minibus if text.include?("市民小巴")
      return :trunk if text.include?("幹線")
      return :taoyuan_trunk if city_id.to_s == "Taoyuan" && taoyuan_trunk_route?(text)
      return :taoyuan_tourist if city_id.to_s == "Taoyuan" && text.match?(TAOYUAN_TOURIST)
      return :taoyuan_free if city_id.to_s == "Taoyuan" && text.match?(/\AL/i)
      return :taoyuan_xingfu if city_id.to_s == "Taoyuan" && text.match?(/\AT/i)
      return :maokong if text.include?("貓空")
      return :beishi if text.start_with?("北士科")
      return :huaien if text.include?("懷恩")
      return :leapfrog if text.include?("跳蛙")
      # Named “xx線” (吉林線、大樹線、三鶯2線(原812)…); OD labels like 三峽-內科 stay elsewhere.
      # Numbered expresses that keep a trailing 線 in the TDX name (982直達新埔線)
      # stay with their hundreds band, not 地區線.
      stripped = text.sub(/（[^）]*）|\([^)]*\)\z/, "")
      return :named_line if stripped.match?(/線\z/) && !stripped.match?(/\A\d/)
      # Place-to-place leapfrog refs (汐止-台北101) may embed digits that are not route numbers.
      return :leapfrog if od_place_label?(text)
      return OTHER_BAND if route_number(text).nil?

      hundreds_band(text)
    end

    def taoyuan_trunk_route?(ref)
      number = ref.to_s[/\A(\d+)/, 1]&.to_i
      number&.between?(1, 100) || false
    end

    # Trunk name for a Taoyuan 1–100 ref, or nil when the route has none.
    def taoyuan_trunk_name(ref)
      text = ref.to_s.strip
      return nil if text.empty? || TAOYUAN_TRUNK_NAME_EXCEPTIONS.include?(text)

      named = TAOYUAN_TRUNK_NAMES[text]
      return named if named

      base = text[/\A\d+/]
      return nil if base.blank? || base == text

      TAOYUAN_TRUNK_NAMES[base]
    end

    def taoyuan_trunk_names_payload
      { "names" => TAOYUAN_TRUNK_NAMES, "exceptions" => TAOYUAN_TRUNK_NAME_EXCEPTIONS }
    end

    # OD labels use hyphens between places; numbered/letter-coded refs keep hundreds bands
    # (716(台灣好行-…), T517梅山-旗山, F123-0640).
    def od_place_label?(ref)
      text = ref.to_s.strip
      return false unless text.match?(/[-－—]/)
      return false if text.match?(/\A[\dA-Za-z]/)

      true
    end

    def hundreds_band_label(band)
      return nil unless band.is_a?(Integer)
      return "0-99" if band.zero?
      return "1000+" if band >= 1000

      "#{band}-#{band + 99}"
    end

    # On-disk folder names must stay ASCII (git, URLs, shells). Labels stay in i18n.
    SPECIAL_BAND_DIRS = {
      keelung_tr: "r-t",
      taoyuan_trunk: "taoyuan-trunk",
      taoyuan_tourist: "taoyuan-tourist",
      taoyuan_free: "taoyuan-free",
      taoyuan_xingfu: "taoyuan-xingfu",
      metro_feeder: "metro-feeder",
      loop_line: "loop",
      color_hong: "hong",
      color_lan: "lan",
      color_lu: "lu",
      color_zong: "zong",
      color_ju: "ju",
      color_huang: "huang",
      xiao: "xiao",
      ankeng: "ankeng",
      f_series: "f",
      neike: "neike",
      taipei_tourist: "taipei-tourist",
      nangang_soft: "nangang-soft",
      commuter: "commuter",
      trunk: "trunk",
      civic_minibus: "civic-minibus",
      maokong: "maokong",
      beishi: "beishi",
      huaien: "huaien",
      named_line: "named",
      leapfrog: "leapfrog",
      OTHER_BAND => "other"
    }.freeze

    # Pre-ASCII folder names still found in older checkouts / caches.
    LEGACY_BAND_DIRS = {
      "R, T" => "r-t",
      "紅" => "hong",
      "藍" => "lan",
      "綠" => "lu",
      "棕" => "zong",
      "橘" => "ju",
      "黃" => "huang",
      "小" => "xiao",
      "安坑" => "ankeng",
      "F" => "f",
      "內科通勤" => "neike",
      "內科快線" => "neike",
      "內科" => "neike",
      "臺北觀光巴士" => "taipei-tourist",
      "台北觀光巴士" => "taipei-tourist",
      "南軟" => "nangang-soft",
      "通勤" => "commuter",
      "幹線" => "trunk",
      "市民小巴" => "civic-minibus",
      "貓空" => "maokong",
      "北士科" => "beishi",
      "懷恩專車" => "huaien",
      "路線" => "named",
      "跳蛙" => "leapfrog",
      "跳蛙公車" => "leapfrog"
    }.freeze

    def browse_band_dir(ref, city_id: nil)
      band = browse_band(ref, city_id:)
      case band
      when Integer
        hundreds_band_label(band)
      when Symbol
        SPECIAL_BAND_DIRS[band] || band.to_s
      else
        "other"
      end
    end

    def browse_band_key(band)
      case band
      when Integer then band.to_s
      when Symbol then band.to_s
      else OTHER_BAND.to_s
      end
    end

    def parse_browse_band_key(value)
      text = value.to_s.strip
      return nil if text.blank?
      return text.to_i if text.match?(/\A\d+\z/)

      text.to_sym
    end

    def special_band?(band)
      band.is_a?(Symbol)
    end

    def browse_band_sort_key(band)
      # Keep Keelung T/R and Taoyuan trunk buses where 0–99 used to appear.
      return [ 0, -1 ] if band == :keelung_tr
      return [ 0, 0 ] if band == :taoyuan_trunk
      return [ 0, 499 ] if band == :taoyuan_tourist

      case band
      when Integer
        [ 0, band ]
      when Symbol
        [ 1, SPECIAL_BAND_ORDER.index(band) || SPECIAL_BAND_ORDER.length ]
      else
        [ 2, 0 ]
      end
    end

    def group_by_hundreds(routes)
      Array(routes)
        .group_by { |route| browse_band(route["ref"], city_id: route["city_id"]) }
        .sort_by { |band, _routes| browse_band_sort_key(band) }
    end

    # Digest used by BusTimedDetours / 經三總 importer splits for the campus path.
    CAMPUS_DETOUR_SLUG = Digest::SHA1.hexdigest("繞駛三總")[0, 10].freeze

    # 繞駛三總 (campus inside) above the timed / 不經三總 sibling in the sidebar.
    def campus_span_rank(route)
      case route["campus_span"]
      when "inside" then 0
      when "outside" then 2
      else
        via = route["via"].to_s
        id = route["id"].to_s
        if via.include?("不繞駛三總")
          2
        elsif via.include?("繞駛三總") || id.end_with?("_#{CAMPUS_DETOUR_SLUG}") || id.include?("_#{CAMPUS_DETOUR_SLUG}_")
          0
        else
          1
        end
      end
    end

    def sort_routes(routes)
      Array(routes).sort_by do |route|
        [ route["ref"].to_s[/\d+/].to_i, route["ref"].to_s, campus_span_rank(route), route["id"].to_s ]
      end
    end

    # Highway-coach operators are assigned numeric blocks (國光 18xx, 和欣 75xx…).
    # Cluster route numbers so the sidebar can show e.g. "1751–1881、7000–7005".
    OPERATOR_REF_GAP = 100
    OPERATOR_REF_MAX_CLUSTERS = 5

    def operator_ref_ranges(routes, gap: OPERATOR_REF_GAP, max_clusters: OPERATOR_REF_MAX_CLUSTERS)
      numbers = Array(routes).filter_map { |route| route_number(route["ref"]) }.uniq.sort
      return [] if numbers.empty?

      clusters = []
      numbers.each do |number|
        if clusters.empty? || (number - clusters.last.last) > gap
          clusters << [ number ]
        else
          clusters.last << number
        end
      end

      labels = clusters.first(max_clusters).map do |cluster|
        low, high = cluster.first, cluster.last
        low == high ? low.to_s : "#{low}–#{high}"
      end
      labels << "…" if clusters.length > max_clusters
      labels
    end
  end
end
