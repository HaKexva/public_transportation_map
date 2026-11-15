# frozen_string_literal: true

module Geojson
  # Some routes keep the same path but skip named stops in set windows
  # (eBus headway notes such as 「平常日時段…不停靠…」). Tag those stops
  # and stamp a route-level service_note; do not drop geometry.
  module BusTimedSkips
    # city_id => ref => rule or [rule, ...]
    # 自來水處(辛亥): 辛亥路(木柵)轉基隆路(福和橋)的車，尖峰時段不停該站。
    XINHAI_WATER_SKIP = {
      days: "daily",
      windows: [ %w[07:00 09:00], %w[17:00 19:00] ],
      stops: [ "自來水處(辛亥)" ],
      note: "每日 07:00–09:00、17:00–19:00 不停自來水處(辛亥)",
      note_en: "Daily 07:00–09:00 and 17:00–19:00: no stop at Taipei Water Department (Xinhai)"
    }.freeze

    # eBus: 「陽明戲院」(往捷運劍潭站方向)站位，僅上午11:00前班次停靠
    # (紅7／紅7區, 平日與假日同). After 11:00 that inbound stop is skipped.
    YANGMING_THEATER_SKIP = {
      days: "daily",
      windows: [ %w[11:00 24:00] ],
      stops: [ "陽明戲院" ],
      note: "每日 11:00 後往捷運劍潭站方向不停陽明戲院",
      note_en: "Daily after 11:00 toward MRT Jiantan: no stop at Yangming Theater"
    }.freeze

    RULES = {
      "Taipei" => {
        "673" => XINHAI_WATER_SKIP,
        "907" => XINHAI_WATER_SKIP,
        "棕12" => XINHAI_WATER_SKIP,
        "棕22" => XINHAI_WATER_SKIP,
        # 往社子 always stops; 返程往劍潭 only before 11:00.
        "紅7" => YANGMING_THEATER_SKIP.merge(directions: [ 1 ]),
        # 往劍潭 is direction 0; TDX omits the stop on that board, so ensure it.
        "紅7區" => YANGMING_THEATER_SKIP.merge(
          directions: [ 0 ],
          ensure_stops: [
            {
              direction: 0,
              before: "捷運劍潭站(中山)",
              name: "陽明戲院",
              name_en: "Yangming Theater",
              ref: "TPE57643",
              coordinates: [ 121.5259209, 25.08770498 ]
            }
          ]
        )
      },
      "NewTaipei" => {
        "823" => {
          days: "weekday",
          windows: [ %w[07:30 08:00], %w[12:00 12:30], %w[16:00 16:30] ],
          stops: [ "汐止區行政中心(仁愛路)", "秀峰國小" ],
          note: "平日 07:30–08:00、12:00–12:30、16:00–16:30 不停汐止區行政中心(仁愛路)、秀峰國小",
          note_en: "Weekdays 07:30–08:00, 12:00–12:30, 16:00–16:30: no stop at Xizhi Admin. Center (Renai Rd.) or Xiufeng Elementary"
        },
        # eBus: 09:00以前三峽一站發車不停景觀萬坪公園(公厝仔); ①往程不停…
        # 例假日市民廣場管制: 改走仁愛路→逸仙路→松高路，不停市政府(市府).
        "939" => [
          {
            days: "weekday",
            windows: [ %w[06:00 09:00] ],
            directions: [ 0 ],
            stops: [ "景觀萬坪公園(公厝仔)" ],
            note: "平日 09:00 前三峽一站發車往程不停景觀萬坪公園(公厝仔)",
            note_en: "Weekdays: outbound trips from Sanxia Stop 1 before 09:00 skip Landscape Wanping Park (Gongcuozai)"
          },
          {
            days: "holiday",
            windows: [],
            directions: [ 0 ],
            stops: [ "市政府(市府)" ],
            note: "假日改走逸仙路、松高路，不停市政府(市府)",
            note_en: "Holidays: via Yixian Rd. and Songgao Rd.; skips Taipei City Hall (City Hall Rd.)"
          }
        ]
      }
    }.freeze

    module_function

    def rule_for(city_id, ref)
      RULES.dig(city_id.to_s, ref.to_s)
    end

    def rules_for(city_id, ref)
      rule = rule_for(city_id, ref)
      return [] if rule.nil?

      rule.is_a?(Array) ? rule : [ rule ]
    end

    def apply!(bus_root: Geojson::BusLayout.bus_root)
      Dir.glob(File.join(bus_root, "**", "*.geojson")).sort.count do |path|
        next false if File.basename(path).start_with?("_")

        apply_file!(path)
      rescue JSON::ParserError
        false
      end
    end

    def apply_file!(path)
      data = JSON.parse(File.read(path))
      return false unless annotate!(data)

      File.write(path, "#{JSON.pretty_generate(data)}\n")
      true
    end

    def annotate!(data)
      properties = data["properties"] || {}
      rules = rules_for(properties["city_id"], properties["ref"])
      return false if rules.empty?

      changed = false
      rules.each { |rule| changed = true if apply_rule!(data, rule) }

      notes = rules.filter_map { |rule| rule[:note].to_s.presence }
      notes_en = rules.filter_map { |rule| rule[:note_en].to_s.presence }
      if notes.any?
        joined = notes.join("；")
        joined_en = notes_en.join("; ")
        if properties["service_note"] != joined
          properties["service_note"] = joined
          properties["service_note_en"] = joined_en if joined_en.present?
          data["properties"] = properties
          changed = true
        end
      end

      changed
    end

    def apply_rule!(data, rule)
      changed = ensure_stops!(data, rule)
      stops = Array(rule[:stops]).map(&:to_s)
      return changed if stops.empty?

      directions = Array(rule[:directions]).map(&:to_i)
      desired = {
        "days" => rule[:days].to_s,
        "windows" => Array(rule[:windows]).map { |pair| Array(pair).map(&:to_s) }
      }
      data["features"].each do |feature|
        next unless feature.dig("geometry", "type") == "Point"
        next unless feature.dig("properties", "feature_type") == "station"

        name = feature.dig("properties", "name").to_s
        next unless stops.include?(name)
        next if directions.any? && !directions.include?(feature.dig("properties", "direction").to_i)

        props = feature["properties"]
        next if props["timed_skip"] == desired

        props["timed_skip"] = desired
        changed = true
      end
      changed
    end

    # Insert a stop the published board omits when only some trips serve it
    # (e.g. 紅7區 往劍潭 陽明戲院 before 11:00).
    def ensure_stops!(data, rule)
      specs = Array(rule[:ensure_stops])
      return false if specs.empty?

      changed = false
      features = data["features"]
      specs.each do |spec|
        direction = spec[:direction].to_i
        name = spec[:name].to_s
        next if name.blank?
        next if features.any? { |feature|
          feature.dig("properties", "feature_type") == "station" &&
            feature.dig("properties", "direction").to_i == direction &&
            feature.dig("properties", "name").to_s == name
        }

        anchor = spec[:before].to_s.presence || spec[:after].to_s.presence
        index = features.index { |feature|
          feature.dig("properties", "feature_type") == "station" &&
            feature.dig("properties", "direction").to_i == direction &&
            feature.dig("properties", "name").to_s == anchor
        }
        next unless index

        insert_at = spec[:before].present? ? index : index + 1
        features.insert(insert_at, {
          "type" => "Feature",
          "properties" => {
            "feature_type" => "station",
            "ref" => spec[:ref].to_s,
            "name" => name,
            "name_en" => spec[:name_en].to_s.presence || name,
            "line" => data.dig("properties", "name"),
            "color" => data.dig("properties", "color"),
            "direction" => direction
          }.compact,
          "geometry" => {
            "type" => "Point",
            "coordinates" => Array(spec[:coordinates]).map(&:to_f)
          }
        })
        changed = true
      end
      changed
    end
    private_class_method :apply_rule!, :ensure_stops!
  end
end
