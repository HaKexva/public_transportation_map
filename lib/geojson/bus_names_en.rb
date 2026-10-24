# frozen_string_literal: true

module Geojson
  # English bus route names, via labels and operator names for the English UI.
  #
  # Order of preference: TDX's own RouteName / SubRouteName / OperatorName En
  # (from bus_route_timetables), then a phrase-by-phrase translation using
  # route vocabulary plus place names from bus stops (TDX StopName En), rail
  # stations (config/station_names_en.yml) and OpenStreetMap name:en. Chinese
  # that matches none of them is left as is.
  module BusNamesEn
    OSM_EXTRACTS = %w[tmp/osm/places.geojsonseq tmp/osm/stations.geojsonseq].freeze
    OSM_ROADS = "tmp/osm/roads.geojsonseq"
    HAN = /\p{Han}/

    VOCABULARY = {
      "小黃公車" => "Little Yellow Bus", "幸福巴士" => "Happiness Bus", "幸福" => "Happiness Bus",
      "樂活" => "LOHAS", "台灣好行" => "Taiwan Tourist Shuttle", "臺灣好行" => "Taiwan Tourist Shuttle",
      "市民小巴" => "Citizen Minibus", "幹線" => "Trunk Line", "快線" => "Express", "直達車" => "Direct",
      "直達" => "Direct", "區間車" => "Shuttle", "區間" => "Shuttle", "接駁車" => "Shuttle Bus", "接駁" => "Shuttle",
      "延駛" => "extended to", "延長" => "extended", "副線" => "Sub Line", "本線" => "Main Line", "夜間" => "Night",
      "政大校區" => "NCCU Campus",
      "例假日" => "Holidays", "假日" => "Holiday", "平日" => "Weekday", "週一" => "Mon", "週二" => "Tue",
      "週三" => "Wed", "週四" => "Thu", "週五" => "Fri", "週六" => "Sat", "週日" => "Sun", "寒暑假" => "school holidays",
      "行駛" => "service", "預約" => "reservation", "回程" => "return", "去程" => "outbound", "上午" => "AM",
      "下午" => "PM", "繞駛" => "detour via", "繞經" => "detour via", "不繞" => "skips", "不經" => "skips",
      "經由" => "via", "經" => "via", "繞" => "via", "往" => "to", "至" => "to", "發車" => "departure",
      "火車站" => "Railway Station", "轉運站" => "Transfer Station", "轉運中心" => "Transfer Center",
      "總站" => "Terminal", "車站" => "Station", "站" => "Station", "國小" => "Elementary School",
      "國中" => "Junior High School", "高中" => "Senior High School", "女中" => "Girls' High School",
      "大學" => "University", "醫院" => "Hospital", "市場" => "Market", "公所" => "Township Office",
      "衛生所" => "Health Center", "學區" => "School District", "工業區" => "Industrial Park", "漁港" => "Fishing Harbor",
      "部落" => "Tribe", "社區" => "Community", "線" => "Line", "號" => "No.", "鄰" => "Neighborhood", "專車" => "Bus",
      "公車" => "Bus", "客運" => "Bus", "快捷" => "Express", "不停" => "no stop at", "及" => "and", "和" => "and",
      "縣府" => "County Hall", "市府" => "City Hall", "世博" => "Expo", "醫專" => "Medical College", "先導" => "Pilot",
      "支線" => "Branch", "支" => "Branch", "保養場" => "Depot", "小黃" => "Little Yellow", "高商" => "Commercial High School",
      "高工" => "Industrial High School", "高農" => "Agricultural High School", "交流道" => "Interchange",
      "國道" => "National Freeway", "主題" => "Theme", "路線" => "Route", "路" => "Rd.", "街" => "St.",
      "大道" => "Blvd.", "停駛" => "suspended", "不停靠" => "no stop at", "停靠" => "stops at", "每週" => "every",
      "每周" => "every", "停" => "stops at", "不繞駛" => "skips", "不繞經" => "skips", "改駛" => "rerouted via",
      "延駛至" => "extended to", "延至" => "extended to", "高鐵" => "HSR", "長庚" => "Chang Gung", "一日行程" => "Full-day Tour",
      "半日" => "Half-day", "行程" => "Tour", "外環道" => "Ring Rd.", "東西向快速公路" => "East-West Expressway",
      "快速公路" => "Expressway", "公路" => "Highway", "經國路" => "Jingguo Rd.", "里" => "Village", "村" => "Village",
      "鄉公所" => "Township Office", "鎮公所" => "Township Office", "區公所" => "District Office", "市公所" => "City Office",
      "縣政府" => "County Government", "市政府" => "City Government", "交通" => "Transport", "汽車" => "Motor",
      "租車" => "Car Rental", "車隊" => "Fleet", "遊覽車" => "Tour Bus", "巴士" => "Bus", "運輸" => "Transport",
      "企業" => "Enterprise", "實業" => "Industrial", "國際" => "International", "環狀" => "Circular", "觀光" => "Tourist", "學生" => "Student", "通勤" => "Commuter",
      "紅" => "Red", "藍" => "Blue", "綠" => "Green", "棕" => "Brown", "橘" => "Orange", "黃" => "Yellow", "紫" => "Purple",
      "區" => "Shuttle", "延" => "Ext", "副" => "Sub", "夜" => "Night", "快" => "Express", "東" => "East", "西" => "West",
      "南" => "South", "北" => "North", "上" => "Up", "下" => "Down"
    }.freeze

    module_function

    def reset!
      @snapshot = @phrases = @max_phrase = nil
    end

    # English route name for a full Chinese display name such as
    # "紅1區間車" or "8129A (台東至知本火車站)".
    def name_en(name, ref: nil, city_id: nil)
      text = name.to_s
      return text unless text.match?(HAN)

      if ref.present? && ref.match?(HAN) && (official = official_route_en(city_id, ref)) && text.start_with?(ref)
        text = official + text.delete_prefix(ref)
      end
      translate(text)
    end

    def official_route_en(city_id, ref)
      snapshot[:routes].dig(city_id.to_s, ref.to_s)
    end

    OPERATORS = {
      "捷乘交通有限公司" => "Jiecheng Transport", "捷乘客運" => "Jiecheng Bus", "台灣大車隊" => "Taiwan Taxi",
      "台一大車隊" => "Taiyi Fleet", "皇冠交通股份有限公司" => "Crown Transport", "華聯客運" => "Hualian Bus",
      "泰樂客運" => "Taile Bus", "日豪客運" => "Rihao Bus", "雄獅通運股份有限公司" => "Lion Travel Transport",
      "益泰交通股份有限公司" => "Yitai Transport", "巨業交通(台南)" => "Geya Bus (Tainan)", "九億租車" => "Jiuyi Car Rental",
      "台灣真好" => "Taiwan Zhenhao", "宜展汽車客運" => "Yizhan Bus", "勁揚通運" => "Jinyang Transport",
      "亞盛通運" => "Yasheng Transport", "中華衛星台南車隊" => "Zhonghua Satellite Fleet (Tainan)", "怡美車隊" => "Yimei Fleet",
      "睿奕交通" => "Ruiyi Transport", "亦捷科際" => "Yijie Technology", "南嶽山城合作社" => "Nanyue Shancheng Cooperative",
      "吾拉魯滋合作社" => "Ulaluzi Cooperative", "牡丹灣部落全人文教協會" => "Mudan Bay Tribe Education Association",
      "雲林縣石璧文化發展協會" => "Yunlin Shibi Cultural Development Association", "蘇澳鎮公所" => "Su'ao Township Office"
    }.freeze

    def operator_en(name)
      return if name.blank?

      OPERATORS[name.to_s] || snapshot[:operators][name.to_s].presence ||
        translate(name.to_s.sub(/股份有限公司\z|有限公司\z/, "")).gsub(/\b(Township|District) \1\b/, '\1')
          .then { |english| english unless english.match?(HAN) }
    end

    def translate(text)
      text = text.to_s
      return text unless text.match?(HAN)

      text = text.tr("（），、；：", "(),,;:")
        .gsub(/[台臺](\d+)([甲乙]?)線/) { "Provincial Highway #{Regexp.last_match(1)}#{{ '甲' => 'A', '乙' => 'B' }[Regexp.last_match(2)]}" }
        .gsub(/([一二三四五六七八九十]{1,3})段/) { ", Sec. #{chinese_number(Regexp.last_match(1))}" }
        .gsub(/(\d+)巷/) { " Ln. #{Regexp.last_match(1)}" }.gsub(/(\d+)弄/) { " Aly. #{Regexp.last_match(1)}" }
        .gsub(/(?<=\d)[路號](?=\z|[\s(\-,支])/, "")
        .gsub(/(?<=\d)甲/, "A").gsub(/(?<=\d)乙/, "B")
        .gsub(/\A([紅藍綠棕橘黃紫])(?=\d)/) { VOCABULARY[$1] + " " }
        .gsub(/\A小(?=\d)/, "S")
      out = +""
      after_word = false
      index = 0
      while index < text.length
        if text[index].match?(HAN)
          phrase, english = longest_phrase(text, index)
          append_word(out, english || phrase)
          after_word = english.present?
          index += phrase.length
        else
          char = text[index]
          out << " " if after_word && char.match?(/[A-Za-z0-9]/)
          out << char
          out << " " if char == ","
          after_word = false
          index += 1
        end
      end
      out.gsub(/\s+/, " ").gsub(/\s+,/, ",").gsub(/\(\s+/, "(").gsub(/\s+\)/, ")").strip
    end

    def chinese_number(text)
      digits = { "一" => 1, "二" => 2, "三" => 3, "四" => 4, "五" => 5, "六" => 6, "七" => 7, "八" => 8, "九" => 9 }
      return 10 + digits[text[1]].to_i if text.start_with?("十")
      return digits[text[0]] * 10 + digits[text[2]].to_i if text[1] == "十"

      digits[text]
    end

    def append_word(out, word)
      return if word.blank?

      out << " " if out.present? && !out.end_with?(" ", "(", "-", "/") && !word.match?(/\A[\p{Han})]/)
      out << word
    end

    def longest_phrase(text, index)
      [ max_phrase, text.length - index ].min.downto(1) do |length|
        candidate = text[index, length]
        english = VOCABULARY[candidate] || phrases[candidate]
        return [ candidate, english ] if english
      end
      [ text[index], nil ]
    end

    def phrases
      @phrases ||= Rails.env.test? ? {} : build_phrases
    end

    def phrases=(value)
      @phrases = value
      @max_phrase = nil
    end

    def snapshot=(value)
      @snapshot = value
    end

    def max_phrase
      @max_phrase ||= [ phrases.keys.map(&:length).max.to_i, VOCABULARY.keys.map(&:length).max ].max
    end

    def build_phrases
      votes = Hash.new { |hash, key| hash[key] = Hash.new(0) }
      add = lambda do |zh, en, weight = 1|
        zh = zh.to_s.strip.tr("臺", "台")
        en = en.to_s.strip
        next if zh.length < 2 || en.empty? || en.match?(HAN) || !zh.match?(HAN)

        votes[zh][en] += weight
        votes[zh.tr("台", "臺")][en] += weight
        bare = zh.sub(/[站]\z/, "")
        votes[bare][en.sub(/\s*Station\z/i, "")] += weight if bare != zh && bare.length >= 2
      end

      OSM_EXTRACTS.map { |path| Rails.root.join(path) }.select(&:exist?).each do |path|
        File.foreach(path) do |line|
          next unless line.include?("name:en")

          tags = JSON.parse(line.delete_prefix("\u001e"))["properties"] || {}
          [ tags["name"], tags["name:zh"] ].compact.uniq.each { |zh| add.call(zh, tags["name:en"]) }
        end
      end
      roads = Rails.root.join(OSM_ROADS)
      if roads.exist?
        File.foreach(roads) do |line|
          next unless line.include?("name:en")

          tags = JSON.parse(line.delete_prefix("\u001e"))["properties"] || {}
          zh = tags["name"].to_s
          en = tags["name:en"].to_s
          base_zh = zh.sub(/[一二三四五六七八九十]{1,3}段\z/, "")
          base_en = en.sub(/,?\s*Sec(?:tion|\.)?\s*\d+\s*,?\s*/i, " ").strip
          add.call(base_zh, base_en, 10) if base_zh != zh
          add.call(zh, en, 10) if base_zh == zh
        end
      end
      Geojson::StationNamesEn.dictionary.each { |zh, en| add.call(zh, en, 5) }
      Dir.glob(Geojson::BusLayout.bus_root.join("**/*.geojson")).each do |path|
        Array(JSON.parse(File.read(path))["features"]).each do |feature|
          props = feature["properties"] || {}
          add.call(props["name"], props["name_en"], 3) if props["feature_type"] == "station"
        end
      end
      snapshot[:subroutes].each { |zh, en| add.call(zh, en, 2) }

      votes.transform_values { |counts| counts.max_by { |_en, count| count }.first }
    end

    def snapshot
      @snapshot ||= Rails.env.test? ? { routes: {}, subroutes: {}, operators: {} } : load_snapshot
    end

    def load_snapshot
      routes = Hash.new { |hash, key| hash[key] = {} }
      subroutes = {}
      operators = {}
      BusRouteTimetable.select(:id, :city_id, :routes).find_each do |row|
        city = row.city_id
        Array(row.routes).each do |route|
          zh = route.dig("RouteName", "Zh_tw")
          en = route.dig("RouteName", "En").to_s.strip
          routes[city][zh] = en if zh.to_s.match?(HAN) && en.present? && !en.match?(HAN)
          Array(route["SubRoutes"]).each do |sub|
            sub_zh = sub.dig("SubRouteName", "Zh_tw")
            sub_en = sub.dig("SubRouteName", "En").to_s.strip
            next if sub_en.empty? || sub_en.match?(HAN) || !sub_zh.to_s.match?(HAN)

            routes[city][sub_zh] ||= sub_en
            subroutes[sub_zh] = sub_en
          end
          Array(route["Operators"]).each do |operator|
            op_zh = operator.dig("OperatorName", "Zh_tw")
            op_en = operator.dig("OperatorName", "En").to_s.strip
            operators[op_zh] = op_en if op_zh.present? && op_en.present? && !op_en.match?(HAN)
          end
        end
      end
      { routes:, subroutes:, operators: }
    end

    # Rewrites name_en / via_en / operator_en in the bus GeoJSON files.
    def apply!(bus_root: Geojson::BusLayout.bus_root)
      changed = 0
      Dir.glob(bus_root.join("**/*.geojson")).each do |path|
        data = JSON.parse(File.read(path))
        props = data["properties"] ||= {}
        before = JSON.generate(data)
        city_id = props["city_id"]

        english = name_en(props["name_en"].presence || props["name"], ref: props["ref"], city_id:)
        props["name_en"] = english if english.present?
        props["via_en"] = translate(props["via"]) if props["via"].present?
        if props["operator_en"].blank? && (operator = operator_en(props["operator"]))
          props["operator_en"] = operator
        end
        Array(data["features"]).each do |feature|
          fprops = feature["properties"] || {}
          next unless fprops["feature_type"] == "route"

          fprops["name_en"] = props["name_en"] if props["name_en"].present?
        end
        next if JSON.generate(data) == before

        File.write(path, JSON.pretty_generate(data) + "\n")
        changed += 1
      end
      changed
    end
  end
end
