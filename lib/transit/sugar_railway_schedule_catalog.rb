# frozen_string_literal: true

module Transit
  # Published operating hours / timetables for Taiwan Sugar Railway (糖鐵) routes.
  # Sources cited in each entry's :source; times are approximate and may change
  # with weather, maintenance, or seasonal announcements.
  module SugarRailwayScheduleCatalog
    module Clock
      module_function

      def offset(clock, minutes)
        h, m = clock.split(":").map(&:to_i)
        total = h * 60 + m + minutes
        format("%02d:%02d", (total / 60) % 24, total % 60)
      end
    end

    DATASET_NAME = "糖鐵班表（公開營運時刻整理）"
    SOURCE_NOTE = "整理自台糖及相關公開時刻／營運時間（查詢日約 2026-07）；實際班次以現場／官網公告為準。"

    ROUTES = {
      "qiaotou_sugar_railway" => {
        source: "台糖／台灣糖業博物館橋頭五分車公開說明（例假日固定班；實際以現場公告為準）",
        status: :active,
        calendars: {
          "holiday" => "週六日及國定假日",
          "weekday" => "平日（團體預約）"
        },
        trips: [
          *%w[10:00 10:30 11:00 11:30 13:00 13:30 14:00 14:30 15:00 15:30 16:00 16:30].flat_map.with_index do |clock, index|
            n = index + 1
            [
              {
                calendar: "holiday",
                train_number: "QS-E#{n}",
                direction: TransitRoute::DIRECTION_FORWARD,
                trip_type: "local",
                destination_name: "捷運橋頭糖廠站",
                notes: "例假日五分車；花卉農園中心 → 捷運橋頭糖廠站（約 20–25 分）",
                stops: [
                  [ "高雄花卉農園中心站", clock ],
                  [ "捷運橋頭糖廠站", Clock.offset(clock, 25) ]
                ]
              },
              {
                calendar: "holiday",
                train_number: "QS-W#{n}",
                direction: TransitRoute::DIRECTION_REVERSE,
                trip_type: "local",
                destination_name: "高雄花卉農園中心站",
                notes: "例假日五分車；捷運橋頭糖廠站 → 花卉農園中心",
                stops: [
                  [ "捷運橋頭糖廠站", clock ],
                  [ "高雄花卉農園中心站", Clock.offset(clock, 25) ]
                ]
              }
            ]
          end
        ],
        headways: [
          {
            calendar: "weekday",
            direction: TransitRoute::DIRECTION_BOTH,
            starts_at: "10:00",
            ends_at: "16:00",
            interval_minutes: 60,
            first_departure: "10:00",
            last_departure: "16:00",
            notes: "平日原則採團體預約，無固定個人班次；請洽台糖橋頭園區確認。"
          }
        ]
      },

      "huwei_sugar_railway" => {
        source: "中央社／台糖虎尾糖廠製糖期報導；民間追車整理之季節運蔗班次",
        status: :seasonal_freight,
        calendars: {
          "crushing_season" => "製糖期（約 11/12 月–翌年 3/4 月）"
        },
        trips: [
          {
            calendar: "crushing_season",
            train_number: "HW-F1",
            direction: TransitRoute::DIRECTION_FORWARD,
            trip_type: "freight",
            destination_name: "13番裝車場",
            notes: "運蔗專用、不載客；班次依採收機動，下列為民間整理之常見出發參考",
            stops: [
              [ "虎尾糖廠", "08:00" ],
              [ "13番裝車場", "09:00" ]
            ]
          },
          {
            calendar: "crushing_season",
            train_number: "HW-F2",
            direction: TransitRoute::DIRECTION_FORWARD,
            trip_type: "freight",
            destination_name: "13番裝車場",
            notes: "運蔗專用、不載客",
            stops: [
              [ "虎尾糖廠", "08:15" ],
              [ "13番裝車場", "09:15" ]
            ]
          },
          {
            calendar: "crushing_season",
            train_number: "HW-F3",
            direction: TransitRoute::DIRECTION_FORWARD,
            trip_type: "freight",
            destination_name: "13番裝車場",
            notes: "運蔗專用、不載客",
            stops: [
              [ "虎尾糖廠", "11:00" ],
              [ "13番裝車場", "12:00" ]
            ]
          },
          {
            calendar: "crushing_season",
            train_number: "HW-F4",
            direction: TransitRoute::DIRECTION_FORWARD,
            trip_type: "freight",
            destination_name: "13番裝車場",
            notes: "運蔗專用、不載客",
            stops: [
              [ "虎尾糖廠", "14:00" ],
              [ "13番裝車場", "15:00" ]
            ]
          }
        ],
        headways: [
          {
            calendar: "crushing_season",
            direction: TransitRoute::DIRECTION_BOTH,
            starts_at: "08:00",
            ends_at: "17:00",
            interval_minutes: 180,
            first_departure: "08:00",
            last_departure: "14:00",
            notes: "全台僅存載蔗糖鐵（馬公厝線）。非觀光載客；製糖期每日數班往返虎尾糖廠與裝車場，實際開行依採收／天候調整。"
          }
        ]
      },

      "suantou_sugar_railway" => {
        source: "台糖官網蒜頭糖廠五分仔車班次（假日固定；平日預約制）",
        status: :active,
        calendars: {
          "holiday" => "假日",
          "weekday" => "平日預約（週一檢修）"
        },
        trips: [
          *%w[09:40 10:30 11:20 13:20 14:20 15:20 16:20].each_with_index.map do |clock, i|
            {
              calendar: "holiday",
              train_number: "STS-NPM#{i + 1}",
              direction: TransitRoute::DIRECTION_FORWARD,
              trip_type: "local",
              destination_name: "故宮南院",
              notes: "故宮南院線（單程約 15 分）；10:30 為機動加開",
              stops: [ [ "蒜頭", clock ], [ "故宮南院", Clock.offset(clock, 15) ] ]
            }
          end,
          *%w[10:05 10:55 11:45 13:50 14:50 15:50 16:40].each_with_index.map do |clock, i|
            {
              calendar: "holiday",
              train_number: "STS-NPR#{i + 1}",
              direction: TransitRoute::DIRECTION_REVERSE,
              trip_type: "local",
              destination_name: "蒜頭",
              notes: "故宮南院線回程",
              stops: [ [ "故宮南院", clock ], [ "蒜頭", Clock.offset(clock, 15) ] ]
            }
          end,
          *%w[09:30 10:55 13:40 15:40].each_with_index.map do |clock, i|
            {
              calendar: "holiday",
              train_number: "STS-HSR#{i + 1}",
              direction: TransitRoute::DIRECTION_FORWARD,
              trip_type: "local",
              destination_name: "五分車高鐵站",
              notes: "嘉義高鐵線（單程約 30 分）",
              stops: [ [ "蒜頭", clock ], [ "五分車高鐵站", Clock.offset(clock, 30) ] ]
            }
          end,
          *%w[10:15 11:40 14:25 16:15].each_with_index.map do |clock, i|
            {
              calendar: "holiday",
              train_number: "STS-HSRR#{i + 1}",
              direction: TransitRoute::DIRECTION_REVERSE,
              trip_type: "local",
              destination_name: "蒜頭",
              notes: "嘉義高鐵線回程",
              stops: [ [ "五分車高鐵站", clock ], [ "蒜頭", Clock.offset(clock, 30) ] ]
            }
          end
        ],
        headways: [
          {
            calendar: "weekday",
            direction: TransitRoute::DIRECTION_BOTH,
            starts_at: "09:30",
            ends_at: "16:30",
            interval_minutes: 120,
            first_departure: "09:30",
            last_departure: "16:00",
            notes: "平日採 30 人以上預約、機動發車；週一檢修不營運（遇假日順延）。"
          }
        ]
      },

      "wushulin_sugar_railway" => {
        source: "台糖烏樹林休閒園區 FAQ 五分車發車時間",
        status: :active,
        calendars: {
          "holiday" => "週六日及國定假日",
          "weekday" => "平日（滿 20 人）"
        },
        trips: [
          *%w[09:00 10:30 11:30 13:30 14:30 15:30 16:30].each_with_index.map do |clock, i|
            {
              calendar: "holiday",
              train_number: "WS#{i + 1}",
              direction: TransitRoute::DIRECTION_BOTH,
              trip_type: "local",
              destination_name: "新頂埤",
              notes: "烏樹林 ↔ 新頂埤來回約 50 分／5.1 km；假日固定班、不限人數",
              stops: [ [ "烏樹林", clock ], [ "新頂埤", Clock.offset(clock, 25) ] ]
            }
          end,
          {
            calendar: "weekday",
            train_number: "WS-WD1",
            direction: TransitRoute::DIRECTION_BOTH,
            trip_type: "local",
            destination_name: "新頂埤",
            notes: "平日上午班；僅團體預約或現場滿 20 人發車",
            stops: [ [ "烏樹林", "10:00" ], [ "新頂埤", "10:25" ] ]
          },
          {
            calendar: "weekday",
            train_number: "WS-WD2",
            direction: TransitRoute::DIRECTION_BOTH,
            trip_type: "local",
            destination_name: "新頂埤",
            notes: "平日下午班；僅團體預約或現場滿 20 人發車",
            stops: [ [ "烏樹林", "14:30" ], [ "新頂埤", "14:55" ] ]
          }
        ]
      },

      "guangfu_sugar_railway" => {
        source: "台糖花蓮觀光糖廠 FAQ／園區介紹（目前無定期五分車載客）",
        status: :inactive,
        calendars: { "park" => "園區開放" },
        headways: [
          {
            calendar: "park",
            direction: TransitRoute::DIRECTION_BOTH,
            starts_at: "08:00",
            ends_at: "19:00",
            interval_minutes: 1440,
            first_departure: "08:00",
            last_departure: "08:00",
            notes: "花蓮觀光糖廠（光復）目前無定期五分車載客班次；園區冰店／展售中心平日約 08:00–19:00、假日至 20:00。軌道遺跡供參觀。"
          }
        ]
      },

      "xihu_sugar_tourist_railway" => {
        source: "台糖溪湖糖廠蒸汽觀光五分車／彰化縣觀光資訊",
        status: :active,
        calendars: {
          "holiday" => "例假日柴油固定班",
          "sunday_steam" => "週日蒸汽火車",
          "weekday" => "平日預約"
        },
        trips: [
          *%w[10:00 11:00 13:00 14:00 15:00 16:00].each_with_index.map do |clock, i|
            {
              calendar: "holiday",
              train_number: "XT-D#{i + 1}",
              direction: TransitRoute::DIRECTION_BOTH,
              trip_type: "local",
              destination_name: "草埔",
              notes: "柴油五分車；溪湖 ↔ 草埔來回約 35 分／4.26 km（中午 12:00 休息）",
              stops: [ [ "溪湖", clock ], [ "草埔", Clock.offset(clock, 18) ] ]
            }
          end,
          {
            calendar: "sunday_steam",
            train_number: "XT-S1",
            direction: TransitRoute::DIRECTION_BOTH,
            trip_type: "local",
            destination_name: "草埔",
            notes: "週日蒸汽火車（以現場公告為準）",
            stops: [ [ "溪湖", "11:00" ], [ "草埔", "11:18" ] ]
          },
          {
            calendar: "sunday_steam",
            train_number: "XT-S2",
            direction: TransitRoute::DIRECTION_BOTH,
            trip_type: "local",
            destination_name: "草埔",
            notes: "週日蒸汽火車（以現場公告為準）",
            stops: [ [ "溪湖", "14:00" ], [ "草埔", "14:18" ] ]
          }
        ],
        headways: [
          {
            calendar: "weekday",
            direction: TransitRoute::DIRECTION_BOTH,
            starts_at: "10:00",
            ends_at: "16:00",
            interval_minutes: 60,
            first_departure: "10:00",
            last_departure: "16:00",
            notes: "非假日需 20 人以上預約方發車。"
          }
        ]
      }
    }.freeze
  end
end
