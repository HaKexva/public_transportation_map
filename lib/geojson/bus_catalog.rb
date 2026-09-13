# frozen_string_literal: true

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
      :color_hong,
      :color_lan,
      :color_lu,
      :color_zong,
      :color_ju,
      :color_huang,
      :xiao,
      :ankeng,
      :f_series,
      :neike_commuter,
      :neike_express,
      :nangang_soft,
      :commuter,
      :trunk,
      :civic_minibus,
      :maokong,
      :beishi,
      :huaien,
      :named_line,
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
        operator_id = route["operator_id"].to_s
        next if city_id.empty? || operator_id.empty?

        grouped[city_id][operator_id] ||= {
          "id" => operator_id,
          "name" => route["operator"].to_s.presence || operator_id,
          "name_en" => route["operator_en"].to_s.presence
        }
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

        operator_allow.include?(route["operator_id"].to_s)
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

      COLOR_PREFIX_BANDS.each do |prefix, band|
        return band if text.start_with?(prefix)
      end

      return :xiao if text.match?(/\A小\d/)
      return :ankeng if text.start_with?("安坑")
      return :f_series if text.match?(/\AF\d/i)
      return :nangang_soft if text.include?("南軟")
      return :neike_express if text.include?("內科快線")
      return :neike_commuter if text.include?("內科通勤")
      return :commuter if text.match?(/\A通勤/)
      return :civic_minibus if text.include?("市民小巴")
      return :trunk if text.include?("幹線")
      return :maokong if text.include?("貓空")
      return :beishi if text.start_with?("北士科")
      return :huaien if text.include?("懷恩")
      # Named “xx線” (吉林線、大樹線、三鶯2線(原812)…); OD labels like 三峽-內科 stay elsewhere.
      stripped = text.sub(/（[^）]*）|\([^)]*\)\z/, "")
      return :named_line if stripped.match?(/線\z/)
      # Place-to-place refs (汐止-台北101) may embed digits that are not route numbers.
      return OTHER_BAND if od_place_label?(text)
      return OTHER_BAND if route_number(text).nil?

      hundreds_band(text)
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

    SPECIAL_BAND_DIRS = {
      keelung_tr: "R, T",
      color_hong: "紅",
      color_lan: "藍",
      color_lu: "綠",
      color_zong: "棕",
      color_ju: "橘",
      color_huang: "黃",
      xiao: "小",
      ankeng: "安坑",
      f_series: "F",
      neike_commuter: "內科通勤",
      neike_express: "內科快線",
      nangang_soft: "南軟",
      commuter: "通勤",
      trunk: "幹線",
      civic_minibus: "市民小巴",
      maokong: "貓空",
      beishi: "北士科",
      huaien: "懷恩專車",
      named_line: "路線",
      OTHER_BAND => "other"
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

    def special_band?(band)
      band.is_a?(Symbol)
    end

    def browse_band_sort_key(band)
      # Keep Keelung T/R where 0–99 used to appear (before 100–199).
      return [ 0, -1 ] if band == :keelung_tr

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

    def sort_routes(routes)
      Array(routes).sort_by { |route| [ route["ref"].to_s[/\d+/].to_i, route["ref"].to_s, route["id"].to_s ] }
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
