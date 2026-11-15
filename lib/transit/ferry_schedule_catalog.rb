# frozen_string_literal: true

module Transit
  # Representative published times for Geojson::FerryCatalog lines.
  # Urban lines are headways. Island lines are a few daily trips.
  # Weather and seasonal notices override these; lines without an entry are not routed.
  module FerryScheduleCatalog
    NOTE = "公開班次的代表時刻，天候停航或季節調整時以船公司公告為準。"

    ROUTES = {
      "cijin_ferry" => {
        source: "高雄市輪船公司鼓山－旗津線，日間約 10 分一班、航程約 5 分。#{NOTE}",
        headways: [
          { calendar: "daily", direction: "both", start: "06:00", end: "22:00", every: 10, ride: [ 5 ] }
        ]
      },
      "kw2_cijin_ferry" => {
        source: "棧貳庫－旗津海上巴士，日間約 30 分一班。#{NOTE}",
        headways: [
          { calendar: "daily", direction: "both", start: "10:00", end: "18:00", every: 30, ride: [ 15 ] }
        ]
      },
      "tamsui_bali_ferry" => {
        source: "新北市淡水－八里渡船，日間約 15 分一班、航程約 10 分。#{NOTE}",
        headways: [
          { calendar: "daily", direction: "both", start: "07:00", end: "19:00", every: 15, ride: [ 10 ] }
        ]
      },
      "dadaocheng_tamsui_ferry" => {
        source: "淡水河藍色公路（大稻埕－關渡－淡水），日間約 60 分一班。#{NOTE}",
        headways: [
          { calendar: "daily", direction: "both", start: "09:00", end: "17:00", every: 60, ride: [ 30, 25 ] }
        ]
      },
      "tamsui_fishermans_wharf_ferry" => {
        source: "淡水－漁人碼頭客船，日間約 30 分一班。#{NOTE}",
        headways: [
          { calendar: "daily", direction: "both", start: "09:00", end: "18:00", every: 30, ride: [ 20 ] }
        ]
      },
      "liuqiu_ferry" => {
        source: "東港－小琉球東琉線，日間約 30 分一班、航程約 30 分。#{NOTE}",
        headways: [
          { calendar: "daily", direction: "both", start: "07:00", end: "17:30", every: 30, ride: [ 30 ] }
        ]
      },
      "sun_moon_lake_ferry" => {
        source: "日月潭觀光渡輪，日間約 20 分一班。#{NOTE}",
        headways: [
          { calendar: "daily", direction: "both", start: "09:00", end: "17:00", every: 20, ride: [ 8, 12, 10 ] }
        ]
      },
      "green_island_ferry" => {
        source: "富岡－綠島，代表班次航程約 50 分。#{NOTE}",
        trips: [
          { calendar: "daily", direction: "forward", times: [ "09:00", "09:50" ] },
          { calendar: "daily", direction: "forward", times: [ "14:00", "14:50" ] },
          { calendar: "daily", direction: "reverse", times: [ "10:30", "11:20" ] },
          { calendar: "daily", direction: "reverse", times: [ "15:30", "16:20" ] }
        ]
      },
      "orchid_island_ferry" => {
        source: "富岡－蘭嶼，代表班次航程約 2.5 小時。#{NOTE}",
        trips: [
          { calendar: "daily", direction: "forward", times: [ "09:30", "12:00" ] },
          { calendar: "daily", direction: "reverse", times: [ "14:00", "16:30" ] }
        ]
      },
      "budai_penghu_ferry" => {
        source: "布袋－馬公，代表夜間去程與日間回程。#{NOTE}",
        trips: [
          { calendar: "daily", direction: "forward", times: [ "21:00", "02:00" ] },
          { calendar: "daily", direction: "reverse", times: [ "10:00", "15:00" ] }
        ]
      },
      "kaohsiung_penghu_ferry" => {
        source: "高雄－馬公，代表日間去程與夜間回程。#{NOTE}",
        trips: [
          { calendar: "daily", direction: "forward", times: [ "11:00", "16:30" ] },
          { calendar: "daily", direction: "reverse", times: [ "21:30", "03:00" ] }
        ]
      },
      "keelung_matsu_ferry" => {
        source: "基隆－南竿，代表夜航約 10 小時。#{NOTE}",
        trips: [
          { calendar: "daily", direction: "forward", times: [ "21:00", "07:00" ] },
          { calendar: "daily", direction: "reverse", times: [ "09:30", "19:30" ] }
        ]
      }
    }.freeze

    module_function

    def fetch(slug)
      ROUTES[slug.to_s]
    end

    def scheduled?(slug)
      ROUTES.key?(slug.to_s)
    end
  end
end
