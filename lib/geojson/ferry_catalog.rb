# frozen_string_literal: true

module Geojson
  module FerryCatalog
    COLOR = "#0891b2"

    # Pier coordinates prefer OSM amenity=ferry_terminal / marina nodes when available.

    # 高雄 鼓山－旗津渡輪：鼓山輪渡站 ↔ 旗津輪渡站（高市輪船）。
    CIJIN_FALLBACK_STATIONS = [
      { ref: "CJ01", name: "鼓山輪渡站", name_en: "Gushan Ferry Terminal", lon: 120.2847, lat: 22.6195 },
      { ref: "CJ02", name: "旗津輪渡站", name_en: "Cijin Ferry Terminal", lon: 120.2698, lat: 22.6139 }
    ].freeze

    # 高雄 棧貳庫－旗津海上巴士：棧貳庫 KW2 海側 ↔ 旗津輪渡站。
    KW2_CIJIN_FALLBACK_STATIONS = [
      { ref: "KW01", name: "棧貳庫碼頭", name_en: "KW2 Pier", lon: 120.2765, lat: 22.6185 },
      { ref: "KW02", name: "旗津輪渡站", name_en: "Cijin Ferry Terminal", lon: 120.2698, lat: 22.6139 }
    ].freeze

    # 淡水－八里渡輪：淡水渡船頭 ↔ 八里渡船頭。
    TAMSUI_BALI_FALLBACK_STATIONS = [
      { ref: "TB01", name: "淡水渡船頭", name_en: "Tamsui Ferry Pier", lon: 121.4390, lat: 25.1696 },
      { ref: "TB02", name: "八里渡船頭", name_en: "Bali Ferry Pier", lon: 121.4359, lat: 25.1593 }
    ].freeze

    # 淡水河藍色公路：大稻埕 ↔ 關渡 ↔ 淡水客船碼頭。
    DADAOCHENG_TAMSUI_FALLBACK_STATIONS = [
      { ref: "DT01", name: "大稻埕碼頭", name_en: "Dadaocheng Wharf", lon: 121.5073, lat: 25.0567 },
      { ref: "DT02", name: "關渡碼頭", name_en: "Guandu Pier", lon: 121.4612, lat: 25.1207 },
      { ref: "DT03", name: "淡水客船碼頭", name_en: "Tamsui Passenger Pier", lon: 121.4373, lat: 25.1707 }
    ].freeze

    # 淡水－漁人碼頭：淡水客船碼頭 ↔ 漁人碼頭客船碼頭（情人橋側）。
    TAMSUI_FISHERMANS_FALLBACK_STATIONS = [
      { ref: "TF01", name: "淡水客船碼頭", name_en: "Tamsui Passenger Pier", lon: 121.4373, lat: 25.1707 },
      { ref: "TF02", name: "淡水漁人碼頭", name_en: "Tamsui Fisherman's Wharf", lon: 121.4083, lat: 25.1831 }
    ].freeze

    # 東港－小琉球渡輪：東琉線船運服務中心 ↔ 大福漁港。
    LIUQIU_FALLBACK_STATIONS = [
      { ref: "LQ01", name: "東琉線船運服務中心", name_en: "Dongliu Ferry Center", lon: 120.4443, lat: 22.4686 },
      { ref: "LQ02", name: "小琉球大福漁港", name_en: "Liuqiu Dafu Harbor", lon: 120.3746, lat: 22.3342 }
    ].freeze

    # 日月潭觀光渡輪：水社 ↔ 朝霧 ↔ 玄光 ↔ 伊達邵。
    SUN_MOON_LAKE_FALLBACK_STATIONS = [
      { ref: "SML01", name: "水社碼頭", name_en: "Shuishe Pier", lon: 120.9119, lat: 23.8644 },
      { ref: "SML02", name: "朝霧碼頭", name_en: "Chaowu Pier", lon: 120.9162, lat: 23.8675 },
      { ref: "SML03", name: "玄光碼頭", name_en: "Xuanguang Pier", lon: 120.9130, lat: 23.8530 },
      { ref: "SML04", name: "伊達邵碼頭", name_en: "Ita Thao Pier", lon: 120.9288, lat: 23.8496 }
    ].freeze

    # 富岡－綠島渡輪：富岡漁港 ↔ 綠島南寮漁港。
    GREEN_ISLAND_FALLBACK_STATIONS = [
      { ref: "GI01", name: "富岡漁港", name_en: "Fugang Harbor", lon: 121.1925, lat: 22.7917 },
      { ref: "GI02", name: "綠島南寮漁港", name_en: "Green Island Nanliao Harbor", lon: 121.4746, lat: 22.6589 }
    ].freeze

    # 富岡－蘭嶼渡輪：富岡漁港 ↔ 蘭嶼開元港（椰油）。
    ORCHID_ISLAND_FALLBACK_STATIONS = [
      { ref: "OI01", name: "富岡漁港", name_en: "Fugang Harbor", lon: 121.1925, lat: 22.7917 },
      { ref: "OI02", name: "蘭嶼開元港", name_en: "Orchid Island Kaiyuan Harbor", lon: 121.5082, lat: 22.0584 }
    ].freeze

    # 嘉義布袋－澎湖馬公：布袋商港 ↔ 馬公商港。
    BUDAI_PENGHU_FALLBACK_STATIONS = [
      { ref: "BP01", name: "布袋商港", name_en: "Budai Commercial Port", lon: 120.1396, lat: 23.3799 },
      { ref: "BP02", name: "馬公商港", name_en: "Magong Commercial Port", lon: 119.5641, lat: 23.5636 }
    ].freeze

    # 高雄－澎湖馬公：新濱碼頭 ↔ 馬公商港（台華輪等）。
    KAOHSIUNG_PENGHU_FALLBACK_STATIONS = [
      { ref: "KP01", name: "新濱碼頭", name_en: "Xinbin Pier", lon: 120.2726, lat: 22.6199 },
      { ref: "KP02", name: "馬公商港", name_en: "Magong Commercial Port", lon: 119.5641, lat: 23.5636 }
    ].freeze

    # 基隆－馬祖南竿：基隆港西岸客運中心 ↔ 南竿福澳港旅運大樓。
    KEELUNG_MATSU_FALLBACK_STATIONS = [
      { ref: "KM01", name: "基隆港西岸客運中心", name_en: "Keelung West Passenger Terminal", lon: 121.7416, lat: 25.1351 },
      { ref: "KM02", name: "南竿福澳港", name_en: "Nangan Fu'ao Harbor", lon: 119.9436, lat: 26.1612 }
    ].freeze

    FALLBACK_STATIONS_BY_SLUG = {
      "cijin_ferry" => CIJIN_FALLBACK_STATIONS,
      "kw2_cijin_ferry" => KW2_CIJIN_FALLBACK_STATIONS,
      "tamsui_bali_ferry" => TAMSUI_BALI_FALLBACK_STATIONS,
      "dadaocheng_tamsui_ferry" => DADAOCHENG_TAMSUI_FALLBACK_STATIONS,
      "tamsui_fishermans_wharf_ferry" => TAMSUI_FISHERMANS_FALLBACK_STATIONS,
      "liuqiu_ferry" => LIUQIU_FALLBACK_STATIONS,
      "sun_moon_lake_ferry" => SUN_MOON_LAKE_FALLBACK_STATIONS,
      "green_island_ferry" => GREEN_ISLAND_FALLBACK_STATIONS,
      "orchid_island_ferry" => ORCHID_ISLAND_FALLBACK_STATIONS,
      "budai_penghu_ferry" => BUDAI_PENGHU_FALLBACK_STATIONS,
      "kaohsiung_penghu_ferry" => KAOHSIUNG_PENGHU_FALLBACK_STATIONS,
      "keelung_matsu_ferry" => KEELUNG_MATSU_FALLBACK_STATIONS
    }.freeze

    LINES = [
      MetroLine.ferry(
        slug: "cijin_ferry",
        name: "鼓山－旗津渡輪",
        name_en: "Gushan–Cijin Ferry",
        ref: "CJ",
        color: COLOR,
        station_ref_prefix: "CJ"
      ),
      MetroLine.ferry(
        slug: "kw2_cijin_ferry",
        name: "棧貳庫－旗津海上巴士",
        name_en: "KW2–Cijin Sea Bus",
        ref: "KW",
        color: COLOR,
        station_ref_prefix: "KW"
      ),
      MetroLine.ferry(
        slug: "tamsui_bali_ferry",
        name: "淡水－八里渡輪",
        name_en: "Tamsui–Bali Ferry",
        ref: "TB",
        color: COLOR,
        station_ref_prefix: "TB"
      ),
      MetroLine.ferry(
        slug: "dadaocheng_tamsui_ferry",
        name: "大稻埕－關渡－淡水藍色公路",
        name_en: "Dadaocheng–Guandu–Tamsui Blue Highway",
        ref: "DT",
        color: COLOR,
        station_ref_prefix: "DT"
      ),
      MetroLine.ferry(
        slug: "tamsui_fishermans_wharf_ferry",
        name: "淡水－漁人碼頭",
        name_en: "Tamsui–Fisherman's Wharf Ferry",
        ref: "TF",
        color: COLOR,
        station_ref_prefix: "TF"
      ),
      MetroLine.ferry(
        slug: "liuqiu_ferry",
        name: "東港－小琉球渡輪",
        name_en: "Donggang–Liuqiu Ferry",
        ref: "LQ",
        color: COLOR,
        station_ref_prefix: "LQ"
      ),
      MetroLine.ferry(
        slug: "sun_moon_lake_ferry",
        name: "日月潭觀光渡輪",
        name_en: "Sun Moon Lake Ferry",
        ref: "SML",
        color: COLOR,
        station_ref_prefix: "SML"
      ),
      MetroLine.ferry(
        slug: "green_island_ferry",
        name: "富岡－綠島渡輪",
        name_en: "Fugang–Green Island Ferry",
        ref: "GI",
        color: COLOR,
        station_ref_prefix: "GI"
      ),
      MetroLine.ferry(
        slug: "orchid_island_ferry",
        name: "富岡－蘭嶼渡輪",
        name_en: "Fugang–Orchid Island Ferry",
        ref: "OI",
        color: COLOR,
        station_ref_prefix: "OI"
      ),
      MetroLine.ferry(
        slug: "budai_penghu_ferry",
        name: "布袋－馬公渡輪",
        name_en: "Budai–Magong Ferry",
        ref: "BP",
        color: COLOR,
        station_ref_prefix: "BP"
      ),
      MetroLine.ferry(
        slug: "kaohsiung_penghu_ferry",
        name: "高雄－馬公渡輪",
        name_en: "Kaohsiung–Magong Ferry",
        ref: "KP",
        color: COLOR,
        station_ref_prefix: "KP"
      ),
      MetroLine.ferry(
        slug: "keelung_matsu_ferry",
        name: "基隆－南竿渡輪",
        name_en: "Keelung–Nangan Ferry",
        ref: "KM",
        color: COLOR,
        station_ref_prefix: "KM"
      )
    ].freeze
  end
end
