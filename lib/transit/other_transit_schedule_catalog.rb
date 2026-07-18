# frozen_string_literal: true

module Transit
  # Published operating hours / timetables for `other` system routes (cable cars, forest railways, heritage).
  # Sources cited in each entry's :source; times are approximate and may change
  # with weather, maintenance, or seasonal announcements.
  module OtherTransitScheduleCatalog
    module Clock
      module_function

      def offset(clock, minutes)
        h, m = clock.split(":").map(&:to_i)
        total = h * 60 + m + minutes
        format("%02d:%02d", (total / 60) % 24, total % 60)
      end
    end

    DATASET_NAME = "其他運具班表（公開營運時刻整理）"
    SOURCE_NOTE = "整理自各營運單位公開時刻／營運時間（查詢日約 2026-07）；實際班次以現場／官網公告為準。"

    # Each route entry may include:
    # - :source (required) human-readable citation
    # - :status :active / :seasonal_freight / :inactive / :theme_park / :heritage_railbike
    # - :calendars => { code => name }
    # - :headways => [ { calendar:, direction:, starts_at:, ends_at:, interval_minutes:, first_departure:, last_departure:, notes: } ]
    # - :trips => [ { calendar:, train_number:, direction:, trip_type:, destination_name:, notes:, stops: [[name, "HH:MM"], ...] } ]
    ROUTES = {
      "maokong_gondola" => {
        source: "臺北捷運貓空纜車官網營運時間（平常日／例假日；週一保養）",
        status: :active,
        calendars: {
          "weekday" => "平常日（週二–日，非國定假日）",
          "holiday" => "例假日",
          "monday_closed" => "週一保養（國定假日或特別公告除外）"
        },
        headways: [
          {
            calendar: "weekday",
            direction: TransitRoute::DIRECTION_BOTH,
            starts_at: "09:00",
            ends_at: "21:00",
            interval_minutes: 2,
            first_departure: "09:00",
            last_departure: "21:00",
            notes: "平常日 09:00–21:00；全程約 17–30 分（依車速）。週一例行保養全日停駛（國定假日／特別公告除外）。"
          },
          {
            calendar: "holiday",
            direction: TransitRoute::DIRECTION_BOTH,
            starts_at: "09:00",
            ends_at: "22:00",
            interval_minutes: 2,
            first_departure: "09:00",
            last_departure: "22:00",
            notes: "例假日 09:00–22:00。強風、雷雨或年度檢修可能停駛，出發前請查貓纜官網。"
          }
        ]
      },

      "taoyuan_airport_skytrain" => {
        source: "桃園國際機場官網航廈電車說明；2026-07-01 起南側（非管制區）停駛公告",
        status: :active,
        calendars: {
          "daily" => "每日",
          "night" => "夜間呼叫"
        },
        headways: [
          {
            calendar: "daily",
            direction: TransitRoute::DIRECTION_BOTH,
            starts_at: "05:00",
            ends_at: "24:00",
            interval_minutes: 4,
            first_departure: "05:00",
            last_departure: "24:00",
            notes: "管制區內（北側）航廈電車維持營運，班距約 2–6 分（05:00–24:00）。2026-07-01 起非管制區（南側）電車停駛，改由 24h 航廈巡迴巴士接駁（日間約 15 分、夜間約 20 分）。"
          },
          {
            calendar: "night",
            direction: TransitRoute::DIRECTION_BOTH,
            starts_at: "00:00",
            ends_at: "05:00",
            interval_minutes: 15,
            first_departure: "00:00",
            last_departure: "05:00",
            notes: "00:00–05:00 採呼叫模式：乘客於月台按夜間搭車按鈕呼叫電車。"
          }
        ]
      },

      "sun_moon_ropeway" => {
        source: "日月潭纜車官網營業時間（ropeway.com.tw）",
        status: :active,
        calendars: {
          "weekday" => "平日",
          "holiday" => "假日",
          "maintenance" => "每月第一個星期三保養"
        },
        headways: [
          {
            calendar: "weekday",
            direction: TransitRoute::DIRECTION_BOTH,
            starts_at: "10:30",
            ends_at: "16:00",
            interval_minutes: 5,
            first_departure: "10:30",
            last_departure: "16:00",
            notes: "平日 10:30–16:00（售票約至 15:30）。單程約 7–10 分。每月第一個星期三原則停機保養；櫻花季等可能延長。"
          },
          {
            calendar: "holiday",
            direction: TransitRoute::DIRECTION_BOTH,
            starts_at: "10:00",
            ends_at: "16:30",
            interval_minutes: 5,
            first_departure: "10:00",
            last_departure: "16:30",
            notes: "假日 10:00–16:30（售票約至 16:00）。天候／停電／年度大保養可能調整，以現場公告為準。"
          }
        ]
      },

      "taipingshan_forest_railway" => {
        source: "林業保育署宜蘭分署／台灣山林悠遊網太平山蹦蹦車時刻（全線復駛後）",
        status: :active,
        calendars: {
          "daily" => "每日",
          "summer_extra" => "7–8 月每日／6、9 月國定例假日加班",
          "maintenance" => "每月第二、四個星期二保養"
        },
        trips: [
          *%w[07:30 08:30 09:30 10:30 11:30 12:30 13:30 14:30].each_with_index.flat_map do |clock, i|
            return_clock = Clock.offset(clock, 90)
            [
              {
                calendar: "daily",
                train_number: "TP-OUT#{i + 1}",
                direction: TransitRoute::DIRECTION_FORWARD,
                trip_type: "local",
                destination_name: "茂興",
                notes: "太平山 → 茂興（單程約 20 分）；來回票，指定返程時段",
                stops: [ [ "太平山", clock ], [ "茂興", Clock.offset(clock, 20) ] ]
              },
              {
                calendar: "daily",
                train_number: "TP-IN#{i + 1}",
                direction: TransitRoute::DIRECTION_REVERSE,
                trip_type: "local",
                destination_name: "太平山",
                notes: "茂興 → 太平山（對應去程指定返程）",
                stops: [ [ "茂興", return_clock ], [ "太平山", Clock.offset(return_clock, 20) ] ]
              }
            ]
          end,
          {
            calendar: "summer_extra",
            train_number: "TP-OUT9",
            direction: TransitRoute::DIRECTION_FORWARD,
            trip_type: "local",
            destination_name: "茂興",
            notes: "加班車（7–8 月每日；6、9 月國定例假日）",
            stops: [ [ "太平山", "15:30" ], [ "茂興", "15:50" ] ]
          },
          {
            calendar: "summer_extra",
            train_number: "TP-IN9",
            direction: TransitRoute::DIRECTION_REVERSE,
            trip_type: "local",
            destination_name: "太平山",
            notes: "加班車返程",
            stops: [ [ "茂興", "17:00" ], [ "太平山", "17:20" ] ]
          }
        ]
      },

      "shengxing_old_mountain_line" => {
        source: "舊山線鐵道自行車官網乘車資訊（A／B／C 路線；預約制）",
        status: :heritage_railbike,
        calendars: {
          "route_a" => "A 路線（勝興→南斷橋秘境）",
          "route_b" => "B 路線（龍騰→勝興）",
          "route_c" => "C 路線（龍騰→6 號隧道）"
        },
        trips: [
          *[
            [ "A1", "09:20", "10:30" ],
            [ "A2", "11:20", "12:30" ],
            [ "A3", "13:50", "15:00" ],
            [ "A4", "15:50", "17:00" ],
            [ "A5", "17:30", "18:40" ]
          ].map do |num, depart, arrive|
            {
              calendar: "route_a",
              train_number: num,
              direction: TransitRoute::DIRECTION_FORWARD,
              trip_type: "local",
              destination_name: "南斷橋秘境",
              notes: "鐵道自行車 A 線；發車前約 30 分取票。A5 四月起假日加開。",
              stops: [ [ "勝興", depart ], [ "魚藤坪", arrive ] ]
            }
          end,
          *[
            [ "B1", "09:30", "10:50" ],
            [ "B2", "11:30", "12:50" ],
            [ "B3", "14:00", "15:20" ],
            [ "B4", "16:00", "17:20" ]
          ].map do |num, depart, arrive|
            {
              calendar: "route_b",
              train_number: num,
              direction: TransitRoute::DIRECTION_FORWARD,
              trip_type: "local",
              destination_name: "勝興",
              notes: "鐵道自行車 B 線（不經魚藤坪鐵橋）",
              stops: [ [ "龍騰", depart ], [ "勝興", arrive ] ]
            }
          end,
          *[
            [ "C1", "09:10", "10:30" ],
            [ "C2", "11:10", "12:30" ],
            [ "C3", "13:40", "15:00" ],
            [ "C4", "15:40", "17:00" ],
            [ "C5", "17:30", "18:50" ]
          ].map do |num, depart, arrive|
            {
              calendar: "route_c",
              train_number: num,
              direction: TransitRoute::DIRECTION_FORWARD,
              trip_type: "local",
              destination_name: "6號隧道",
              notes: "鐵道自行車 C 線（經魚藤坪鐵橋）。C5 四月起假日加開。",
              stops: [ [ "龍騰", depart ], [ "魚藤坪", arrive ] ]
            }
          end
        ]
      },

      "jianhushan_ropeway" => {
        source: "劍湖山世界園區設施（園內纜車／接駁；營運隨開園時間）",
        status: :theme_park,
        calendars: { "park" => "園區開放日" },
        headways: [
          {
            calendar: "park",
            direction: TransitRoute::DIRECTION_BOTH,
            starts_at: "09:00",
            ends_at: "17:00",
            interval_minutes: 10,
            first_departure: "09:00",
            last_departure: "17:00",
            notes: "園區內纜車／接駁設施，隨遊樂園開園時段營運（常見約 09:00–17:00）；無獨立對外大眾運輸班表，以園區當日公告為準。"
          }
        ]
      },

      "eda_ropeway" => {
        source: "義大遊樂世界營業時間；園區內纜車／接駁隨開園",
        status: :theme_park,
        calendars: { "park" => "園區開放日" },
        headways: [
          {
            calendar: "park",
            direction: TransitRoute::DIRECTION_BOTH,
            starts_at: "09:00",
            ends_at: "17:30",
            interval_minutes: 10,
            first_departure: "09:00",
            last_departure: "17:30",
            notes: "義大園區營業時間約 09:00–17:30；園內纜車／接駁無獨立對外班表，設施於開園後陸續開放、閉園前陸續關閉，以現場公告為準。"
          }
        ]
      },

      "wulai_trolley" => {
        source: "林業保育署新竹分署／台灣山林悠遊網烏來台車（隨到隨開）",
        status: :active,
        calendars: {
          "daily" => "每日",
          "summer" => "7–8 月延長",
          "maintenance" => "每月第一個星期二保養"
        },
        headways: [
          {
            calendar: "daily",
            direction: TransitRoute::DIRECTION_BOTH,
            starts_at: "09:00",
            ends_at: "17:00",
            interval_minutes: 10,
            first_departure: "09:00",
            last_departure: "17:00",
            notes: "烏來 ↔ 瀑布（約 1.5 km）；隨到隨開。每月第一個星期二保養停駛。"
          },
          {
            calendar: "summer",
            direction: TransitRoute::DIRECTION_BOTH,
            starts_at: "09:00",
            ends_at: "18:00",
            interval_minutes: 10,
            first_departure: "09:00",
            last_departure: "18:00",
            notes: "7–8 月末班延長至 18:00；以現場公告為準。"
          }
        ]
      },

      "shenao_rail_bike" => {
        source: "深澳鐵道自行車官網票價時刻（railbike.com.tw；預約制）",
        status: :heritage_railbike,
        calendars: {
          "daily" => "日間固定班",
          "group_only" => "團體專線（官網不開放）",
          "summer_night" => "夏季夜間「星臨騎境」（約 7/1–8/31）"
        },
        trips: [
          {
            calendar: "group_only",
            train_number: "RB-E09",
            direction: TransitRoute::DIRECTION_FORWARD,
            trip_type: "local",
            destination_name: "深澳",
            notes: "八斗子 → 深澳；平假日官網不開放，僅旅行社／團體（限 20 人以上）電洽",
            stops: [ [ "八斗子", "09:00" ], [ "深澳", "09:30" ] ]
          },
          {
            calendar: "group_only",
            train_number: "RB-W0930",
            direction: TransitRoute::DIRECTION_REVERSE,
            trip_type: "local",
            destination_name: "八斗子",
            notes: "深澳 → 八斗子；團體專線",
            stops: [ [ "深澳", "09:30" ], [ "八斗子", "10:00" ] ]
          },
          *%w[10:00 11:00 13:00 14:00 15:00 16:00 17:00].each_with_index.map do |clock, i|
            {
              calendar: "daily",
              train_number: "RB-E#{i + 1}",
              direction: TransitRoute::DIRECTION_FORWARD,
              trip_type: "local",
              destination_name: "深澳",
              notes: "八斗子 → 深澳（單程約 30 分／1.3 km）；中午 12:00 不發車；須預約",
              stops: [ [ "八斗子", clock ], [ "深澳", Clock.offset(clock, 30) ] ]
            }
          end,
          *%w[10:30 11:30 13:30 14:30 15:30 16:30].each_with_index.map do |clock, i|
            {
              calendar: "daily",
              train_number: "RB-W#{i + 1}",
              direction: TransitRoute::DIRECTION_REVERSE,
              trip_type: "local",
              destination_name: "八斗子",
              notes: "深澳 → 八斗子；須預約",
              stops: [ [ "深澳", clock ], [ "八斗子", Clock.offset(clock, 30) ] ]
            }
          end,
          *%w[18:00 19:00 20:00].each_with_index.map do |clock, i|
            {
              calendar: "summer_night",
              train_number: "RB-NE#{i + 1}",
              direction: TransitRoute::DIRECTION_FORWARD,
              trip_type: "local",
              destination_name: "深澳",
              notes: "夏季夜間八斗子發車（星臨騎境）；以官網當年度公告為準",
              stops: [ [ "八斗子", clock ], [ "深澳", Clock.offset(clock, 30) ] ]
            }
          end,
          *%w[18:30 19:30 20:30].each_with_index.map do |clock, i|
            {
              calendar: "summer_night",
              train_number: "RB-NW#{i + 1}",
              direction: TransitRoute::DIRECTION_REVERSE,
              trip_type: "local",
              destination_name: "八斗子",
              notes: "夏季夜間深澳發車（星臨騎境）",
              stops: [ [ "深澳", clock ], [ "八斗子", Clock.offset(clock, 30) ] ]
            }
          end
        ]
      }
    }.freeze

    module_function

    def Clock.offset(clock, minutes)
      h, m = clock.split(":").map(&:to_i)
      total = h * 60 + m + minutes
      format("%02d:%02d", (total / 60) % 24, total % 60)
    end
  end
end
