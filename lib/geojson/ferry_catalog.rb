# frozen_string_literal: true

module Geojson
  module FerryCatalog
    COLOR = "#0891b2"

    # 高雄 鼓山－旗津渡輪：鼓山輪渡站 ↔ 旗津輪渡站（高市公車處）。
    # OSM way 278501 covers the main crossing channel.
    CIJIN_FALLBACK_STATIONS = [
      { ref: "CJ01", name: "鼓山輪渡站", name_en: "Gushan Ferry Terminal", lon: 120.2847, lat: 22.6289 },
      { ref: "CJ02", name: "旗津輪渡站", name_en: "Cijin Ferry Terminal", lon: 120.2697, lat: 22.6221 }
    ].freeze

    CIJIN_WAY_IDS = [].freeze

    # 淡水－八里渡輪：淡水渡船頭 ↔ 八里左岸碼頭（新北市政府）。
    # OSM way/relation along the Tamsui River estuary.
    TAMSUI_BALI_FALLBACK_STATIONS = [
      { ref: "TB01", name: "淡水渡船頭", name_en: "Tamsui Ferry Pier", lon: 121.4326, lat: 25.1694 },
      { ref: "TB02", name: "八里左岸碼頭", name_en: "Bali Left Bank Pier", lon: 121.4045, lat: 25.1542 }
    ].freeze

    TAMSUI_BALI_WAY_IDS = [ 30442793 ].freeze

    # 東港－小琉球渡輪：東港旅客碼頭 ↔ 小琉球大福漁港（琉球嶼渡輪公司）。
    LIUQIU_FALLBACK_STATIONS = [
      { ref: "LQ01", name: "東港旅客碼頭", name_en: "Donggang Ferry Terminal", lon: 120.4528, lat: 22.4617 },
      { ref: "LQ02", name: "小琉球大福漁港", name_en: "Liuqiu Dafu Harbor", lon: 120.3697, lat: 22.3461 }
    ].freeze

    LIUQIU_WAY_IDS = [].freeze

    # 日月潭觀光渡輪：水社碼頭 ↔ 伊達邵碼頭（日月潭國家風景區）。
    SUN_MOON_LAKE_FALLBACK_STATIONS = [
      { ref: "SML01", name: "水社碼頭", name_en: "Shuishe Pier", lon: 120.9081, lat: 23.8644 },
      { ref: "SML02", name: "朝霧碼頭", name_en: "Chaowu Pier", lon: 120.9003, lat: 23.8700 },
      { ref: "SML03", name: "玄光寺碼頭", name_en: "Xuanguang Temple Pier", lon: 120.9236, lat: 23.8494 },
      { ref: "SML04", name: "伊達邵碼頭", name_en: "Ita Thao Pier", lon: 120.9261, lat: 23.8464 }
    ].freeze

    SUN_MOON_LAKE_WAY_IDS = [].freeze

    # 富岡－綠島渡輪：富岡漁港 ↔ 綠島南寮漁港（綠島之星等）。
    GREEN_ISLAND_FALLBACK_STATIONS = [
      { ref: "GI01", name: "富岡漁港", name_en: "Fugang Harbor", lon: 121.1590, lat: 22.7881 },
      { ref: "GI02", name: "綠島南寮漁港", name_en: "Green Island Nanliao Harbor", lon: 121.4744, lat: 22.6627 }
    ].freeze

    GREEN_ISLAND_WAY_IDS = [].freeze

    # 富岡－蘭嶼渡輪：富岡漁港 ↔ 蘭嶼開元漁港（蘭嶼之星等）。
    ORCHID_ISLAND_FALLBACK_STATIONS = [
      { ref: "OI01", name: "富岡漁港", name_en: "Fugang Harbor", lon: 121.1590, lat: 22.7881 },
      { ref: "OI02", name: "蘭嶼開元漁港", name_en: "Orchid Island Kaiyuan Harbor", lon: 121.5501, lat: 22.0355 }
    ].freeze

    ORCHID_ISLAND_WAY_IDS = [].freeze

    FALLBACK_STATIONS_BY_SLUG = {
      "cijin_ferry" => CIJIN_FALLBACK_STATIONS,
      "tamsui_bali_ferry" => TAMSUI_BALI_FALLBACK_STATIONS,
      "liuqiu_ferry" => LIUQIU_FALLBACK_STATIONS,
      "sun_moon_lake_ferry" => SUN_MOON_LAKE_FALLBACK_STATIONS,
      "green_island_ferry" => GREEN_ISLAND_FALLBACK_STATIONS,
      "orchid_island_ferry" => ORCHID_ISLAND_FALLBACK_STATIONS
    }.freeze

    LINES = [
      MetroLine.ferry(
        slug: "cijin_ferry",
        name: "鼓山－旗津渡輪",
        name_en: "Gushan–Cijin Ferry",
        ref: "CJ",
        color: COLOR,
        way_ids: CIJIN_WAY_IDS,
        station_ref_prefix: "CJ"
      ),
      MetroLine.ferry(
        slug: "tamsui_bali_ferry",
        name: "淡水－八里渡輪",
        name_en: "Tamsui–Bali Ferry",
        ref: "TB",
        color: COLOR,
        way_ids: TAMSUI_BALI_WAY_IDS,
        station_ref_prefix: "TB"
      ),
      MetroLine.ferry(
        slug: "liuqiu_ferry",
        name: "東港－小琉球渡輪",
        name_en: "Donggang–Liuqiu Ferry",
        ref: "LQ",
        color: COLOR,
        way_ids: LIUQIU_WAY_IDS,
        station_ref_prefix: "LQ"
      ),
      MetroLine.ferry(
        slug: "sun_moon_lake_ferry",
        name: "日月潭觀光渡輪",
        name_en: "Sun Moon Lake Ferry",
        ref: "SML",
        color: COLOR,
        way_ids: SUN_MOON_LAKE_WAY_IDS,
        station_ref_prefix: "SML"
      ),
      MetroLine.ferry(
        slug: "green_island_ferry",
        name: "富岡－綠島渡輪",
        name_en: "Fugang–Green Island Ferry",
        ref: "GI",
        color: COLOR,
        way_ids: GREEN_ISLAND_WAY_IDS,
        station_ref_prefix: "GI"
      ),
      MetroLine.ferry(
        slug: "orchid_island_ferry",
        name: "富岡－蘭嶼渡輪",
        name_en: "Fugang–Orchid Island Ferry",
        ref: "OI",
        color: COLOR,
        way_ids: ORCHID_ISLAND_WAY_IDS,
        station_ref_prefix: "OI"
      )
    ].freeze
  end
end
