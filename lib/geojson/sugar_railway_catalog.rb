# frozen_string_literal: true

module Geojson
  module SugarRailwayCatalog
    # 高雄花卉農園中心五分車：花卉農園中心 ↔ 捷運橋頭糖廠站（台糖觀光糖鐵）。
    # Track termini from OSM way 41389875; passenger names from Taiwan Sugar Corp.
    QIAOTOU_FALLBACK_STATIONS = [
      { ref: "QS01", name: "高雄花卉農園中心站", lon: 120.3243611, lat: 22.7430259 },
      { ref: "QS02", name: "捷運橋頭糖廠站", lon: 120.3146833, lat: 22.7530305 }
    ].freeze

    # 虎尾糖廠馬公厝線（全台唯一仍載蔗的糖鐵）：糖廠 → 13番裝車場。
    # Named halts from OSM / 時光土場追車攻略; 裝車場 at OSM siding switches.
    HUWEI_FALLBACK_STATIONS = [
      { ref: "HW01", name: "虎尾糖廠", lon: 120.436782, lat: 23.7036397 },
      { ref: "HW02", name: "後壁寮旗", lon: 120.4206443, lat: 23.7133053 },
      { ref: "HW03", name: "北溪厝", lon: 120.4022841, lat: 23.718958 },
      { ref: "HW04", name: "改良場", lon: 120.3934786, lat: 23.7197258 },
      { ref: "HW05", name: "9番裝車場", lon: 120.3693483, lat: 23.7217789 },
      { ref: "HW06", name: "畜殖場", lon: 120.3655787, lat: 23.7221902 },
      { ref: "HW07", name: "10番裝車場", lon: 120.3475394, lat: 23.724981 },
      { ref: "HW08", name: "11番裝車場", lon: 120.3336536, lat: 23.7282125 },
      { ref: "HW09", name: "12番裝車場", lon: 120.3168411, lat: 23.7284727 },
      { ref: "HW10", name: "13番裝車場", lon: 120.2933787, lat: 23.7288312 }
    ].freeze

    # Magongcuo Line: factory spur → named 馬公厝線 segments → western main → terminus stub.
    HUWEI_WAY_IDS = [
      32602597, 871805094, 871805093,
      337588404, 1172494983, 1172494982, 1172494981, 1172494980,
      48288743, 48288738
    ].freeze

    # 溪湖糖廠蒸汽觀光五分車：溪湖 → 草埔（現行）；濁水為 2022-10 前舊終點（OSM disused）。
    XIHU_TOURIST_FALLBACK_STATIONS = [
      { ref: "XT01", name: "溪湖", lon: 120.4817648, lat: 23.9520499 },
      { ref: "XT02", name: "草埔", lon: 120.4720756, lat: 23.9389581 },
      { ref: "XT03", name: "濁水", lon: 120.4649987, lat: 23.9302967 }
    ].freeze

    XIHU_TOURIST_WAY_IDS = [
      1521591426, 1521591427, 25488903, 1289052580, 1289052579, 1289052565, 1469213558,
      1289052564, 1289052560, 1289052559, 1257094867, 1469213556, 1469213557, 1257094866
    ].freeze

    # 蒜頭蔗埕五分車：蒜頭站 ↔ 故宮南院站／五分車高鐵站（台糖時刻表）。
    SUANTOU_FALLBACK_STATIONS = [
      { ref: "STS01", name: "蒜頭站", lon: 120.3008946, lat: 23.4795262 },
      { ref: "STS02", name: "故宮南院站", lon: 120.2922825, lat: 23.476604 },
      { ref: "STS03", name: "五分車高鐵站", lon: 120.3227373, lat: 23.4604896 }
    ].freeze

    # Hub at 蒜頭: west branch to NPM Southern Branch; southeast branch to Chiayi HSR.
    SUANTOU_WAY_IDS = [
      1493548400, 1493548382, 1493549940, 1493549939, 1493590132, 268545951, 1254517077, 1254517076,
      1493550798, 1493550797, 564171770, 1492121271, 1308726730
    ].freeze

    # 烏樹林五分車（新港東線）：烏樹林上車 → 新頂埤折返 → 內埕下車（台糖 FAQ／維基）。
    WUSHULIN_FALLBACK_STATIONS = [
      { ref: "WS01", name: "內埕", lon: 120.373465, lat: 23.3283759 },
      { ref: "WS02", name: "烏樹林", lon: 120.3737764, lat: 23.3286636 },
      { ref: "WS03", name: "新頂埤", lon: 120.3625596, lat: 23.3413741 }
    ].freeze

    # Station loop → north connector → junction → Xingangdong Line to Xindingpi.
    WUSHULIN_WAY_IDS = [
      151002559, 532967414, 532967413, 267615661
    ].freeze

    # 花蓮觀光糖廠遊園小火車：漪漣園旁上車 → 園區導覽 → 花糖文物館（部落格／愛呷宜花東）。
    GUANGFU_FALLBACK_STATIONS = [
      { ref: "GF01", name: "漪漣園", lon: 121.4200843, lat: 23.6585627 },
      { ref: "GF02", name: "花糖文物館", lon: 121.4205619, lat: 23.6594686 }
    ].freeze

    GUANGFU_WAY_IDS = [ 202547164 ].freeze

    FALLBACK_STATIONS_BY_SLUG = {
      "qiaotou_sugar_railway" => QIAOTOU_FALLBACK_STATIONS,
      "huwei_sugar_railway" => HUWEI_FALLBACK_STATIONS,
      "xihu_sugar_tourist_railway" => XIHU_TOURIST_FALLBACK_STATIONS,
      "suantou_sugar_railway" => SUANTOU_FALLBACK_STATIONS,
      "wushulin_sugar_railway" => WUSHULIN_FALLBACK_STATIONS,
      "guangfu_sugar_railway" => GUANGFU_FALLBACK_STATIONS
    }.freeze

    LINES = [
      MetroLine.sugar(
        slug: "qiaotou_sugar_railway",
        name: "橋頭糖鐵",
        name_en: "Qiaotou Sugar Railway",
        ref: "QS",
        color: "#B45309",
        way_ids: [ 41389875 ],
        station_ref_prefix: "QS"
      ),
      MetroLine.sugar(
        slug: "huwei_sugar_railway",
        name: "虎尾糖廠鐵路",
        name_en: "Huwei Sugar Railway",
        ref: "HW",
        color: "#B45309",
        way_ids: HUWEI_WAY_IDS,
        station_ref_prefix: "HW"
      ),
      MetroLine.sugar(
        slug: "suantou_sugar_railway",
        name: "蒜頭蔗埕文化園區五分車",
        name_en: "Suantou Sugar Railway",
        ref: "STS",
        color: "#B45309",
        way_ids: SUANTOU_WAY_IDS,
        station_ref_prefix: "STS"
      ),
      MetroLine.sugar(
        slug: "wushulin_sugar_railway",
        name: "烏樹林糖廠五分車",
        name_en: "Wushulin Sugar Railway",
        ref: "WS",
        color: "#B45309",
        way_ids: WUSHULIN_WAY_IDS,
        station_ref_prefix: "WS"
      ),
      MetroLine.sugar(
        slug: "guangfu_sugar_railway",
        name: "花蓮觀光糖廠五分車",
        name_en: "Hualien Sugar Factory Railway",
        ref: "GF",
        color: "#B45309",
        way_ids: GUANGFU_WAY_IDS,
        station_ref_prefix: "GF"
      ),
      MetroLine.sugar(
        slug: "xihu_sugar_tourist_railway",
        name: "溪湖糖廠蒸汽觀光五分車",
        name_en: "Xihu Sugar Factory Tourist Railway",
        ref: "XT",
        color: "#B45309",
        way_ids: XIHU_TOURIST_WAY_IDS,
        station_ref_prefix: "XT"
      )
    ].freeze
  end
end
