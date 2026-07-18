# frozen_string_literal: true

module Geojson
  module OtherTransitCatalog
    # Type-unified map colors (same mode shares one color).
    COLOR_ROPEWAY = "#0891B2"
    COLOR_FOREST_RAILWAY = "#166534"
    COLOR_SKYTRAIN = "#4F46E5"
    COLOR_TROLLEY = "#0F766E"
    COLOR_RAIL_BIKE = "#7C2D12"

    # Passenger + angle stops along the Maokong Gondola (OSM way 71266575).
    MAOKONG_FALLBACK_STATIONS = [
      { ref: "G1", name: "動物園", lon: 121.5762884, lat: 24.9959573 },
      { ref: "G2", name: "轉角一", lon: 121.5829967, lat: 24.9919382, angle_station: true },
      { ref: "G3", name: "動物園南", lon: 121.5874945, lat: 24.9901573 },
      { ref: "G4", name: "轉角二", lon: 121.5921614, lat: 24.9882953, angle_station: true },
      { ref: "G5", name: "指南宮", lon: 121.5896828, lat: 24.9789312 },
      { ref: "G6", name: "貓空", lon: 121.5881712, lat: 24.9691386 }
    ].freeze

    JIANHUSHAN_FALLBACK_STATIONS = [
      { ref: "JH01", name: "劍湖山世界", lon: 120.5765, lat: 23.6205 },
      { ref: "JH02", name: "劍虎館", lon: 120.5788, lat: 23.6165 }
    ].freeze

    EDA_FALLBACK_STATIONS = [
      { ref: "ED01", name: "義大調酒館", lon: 120.4075, lat: 22.7325 },
      { ref: "ED02", name: "義大皇家酒店", lon: 120.4105, lat: 22.7295 }
    ].freeze

    # 太平山蹦蹦車（茂興線）：太平山站 ↔ 茂興站（林業保育署）。
    TAIPINGSHAN_FALLBACK_STATIONS = [
      { ref: "TP01", name: "太平山", lon: 121.5350854, lat: 24.4928932 },
      { ref: "TP02", name: "茂興", lon: 121.5359008, lat: 24.4783401 }
    ].freeze

    TAIPINGSHAN_WAY_IDS = [
      1055447348, 871805098, 917668180, 871805095, 929727020, 929727245, 344579717
    ].freeze

    # 烏來台車：烏來站 ↔ 瀑布站（林業保育署新竹分署；觀光輕便鐵路）。
    WULAI_FALLBACK_STATIONS = [
      { ref: "WL01", name: "烏來", lon: 121.5511735, lat: 24.8608983 },
      { ref: "WL02", name: "瀑布", lon: 121.5517714, lat: 24.8492141 }
    ].freeze

    WULAI_WAY_IDS = [ 160556314, 523303327 ].freeze

    # 深澳鐵道自行車：八斗子 ↔ 深澳（全長約 1.3 km；OSM tourism disused rail）。
    SHENAO_RAIL_BIKE_FALLBACK_STATIONS = [
      { ref: "RB01", name: "八斗子", lon: 121.80548, lat: 25.13417 },
      { ref: "RB02", name: "深澳", lon: 121.8143802, lat: 25.1289296 }
    ].freeze

    SHENAO_RAIL_BIKE_WAY_IDS = [
      506588363, 506592334, 506592335, 688101944
    ].freeze

    # Major passenger stops along 阿里山線 + 祝山線 (Chiayi–Zhushan).
    ALISHAN_FALLBACK_STATIONS = [
      { ref: "AF01", name: "嘉義", name_en: "Chiayi", lon: 120.4417822, lat: 23.4800692 },
      { ref: "AF02", name: "北門", name_en: "Beimen", lon: 120.4546635, lat: 23.4876235 },
      { ref: "AF03", name: "竹崎", name_en: "Zhuqi", lon: 120.5515, lat: 23.5245 },
      { ref: "AF04", name: "樟腦寮", name_en: "Zhangnaoliao", lon: 120.6026707, lat: 23.5327812 },
      { ref: "AF05", name: "獨立山", name_en: "Dulishan", lon: 120.6074810, lat: 23.5385165 },
      { ref: "AF06", name: "梨園寮", name_en: "Liyuanliao", lon: 120.6200511, lat: 23.5423660 },
      { ref: "AF07", name: "交力坪", name_en: "Jiaoliping", lon: 120.6437657, lat: 23.5314477 },
      { ref: "AF08", name: "水社寮", name_en: "Shuisheliao", lon: 120.6595117, lat: 23.5043486 },
      { ref: "AF09", name: "奮起湖", name_en: "Fenqihu", lon: 120.6949203, lat: 23.5053414 },
      { ref: "AF10", name: "十字路", name_en: "Shizilu", lon: 120.7539935, lat: 23.4927600 },
      { ref: "AF11", name: "阿里山", name_en: "Alishan", lon: 120.8043442, lat: 23.5100028 },
      { ref: "AF12", name: "神木", name_en: "Shenmu", lon: 120.8078884, lat: 23.5187625 },
      { ref: "AF13", name: "沼平", name_en: "Zhaoping", lon: 120.8139361, lat: 23.5144467 },
      { ref: "AF14", name: "對高岳", name_en: "Duigaoyue", lon: 120.8189599, lat: 23.5151880 },
      { ref: "AF15", name: "祝山", name_en: "Zhushan", lon: 120.8234470, lat: 23.5102670 }
    ].freeze

    # OSM ways for in-service 阿里山線 + 祝山線.
    # Includes short connectors (牛稠溪橋) and the Duigaoyue collapsed alignment so the
    # Chiayi–Zhushan corridor stays visually continuous where OSM marks a landslide gap.
    ALISHAN_WAY_IDS = [
      99540299, 229131740, 229131741, 229143337, 229143338, 229143339, 229143340, 229143341,
      229143342, 229143343, 229143344, 229143346, 229143347, 229143348, 229143349, 229143350,
      229143351, 229143352, 229143353, 229143354, 229143355, 229143356, 229143357, 229143358,
      229143359, 229143360, 229143361, 229516472, 229543909, 229543911, 229548208, 229548209,
      229548210, 229548211, 229548212, 229548213, 229548214, 229548215, 229549716, 229549718,
      229549719, 229549720, 229549721, 321233588, 321233589, 340254443, 340254447, 340255673,
      340255674, 340255675, 354269061, 354269062, 460846810, 462911102, 531619993, 531619995,
      545460839, 545460841, 548361500, 548361502, 550540500, 550540502, 550543649, 573029765,
      573029769, 722223568, 722223569, 746106061, 746106063, 789792696, 789792697, 789792698,
      809152961, 809226519, 813657041, 813657042, 814270227, 814270228, 814270229, 814270232,
      814270233, 871803293, 871803294, 871803295, 871803296, 871803297, 871803298, 871803299,
      871803300, 871803301, 871803302, 871803303, 871803304, 1061049345, 1061049350, 1061049351,
      1061049352, 1138466090, 1138466095, 1138466098, 1216098244, 1216098259, 1216098267,
      1216098268, 1216098269, 1216098276, 1216098277, 1216098278, 1216098279, 1216098280,
      1216098281, 1283222394, 1283222395, 1283222396, 1283222397, 1283222398, 1283222399,
      1417976929, 1417976930, 1429734253, 1429734254, 1429734255, 1429734256, 1429750185,
      1429750186, 1429963297, 1429963298, 1462240315, 1462240316
    ].freeze

    FALLBACK_STATIONS_BY_SLUG = {
      "jianhushan_ropeway" => JIANHUSHAN_FALLBACK_STATIONS,
      "eda_ropeway" => EDA_FALLBACK_STATIONS,
      "taipingshan_forest_railway" => TAIPINGSHAN_FALLBACK_STATIONS,
      "wulai_trolley" => WULAI_FALLBACK_STATIONS,
      "alishan_forest_railway" => ALISHAN_FALLBACK_STATIONS,
      "shenao_rail_bike" => SHENAO_RAIL_BIKE_FALLBACK_STATIONS
    }.freeze

    LINES = [
      MetroLine.other(
        slug: "maokong_gondola",
        name: "貓空纜車",
        name_en: "Maokong Gondola",
        ref: "MG",
        color: COLOR_ROPEWAY,
        way_ids: [ 71266575 ],
        station_ref_prefix: "MG"
      ),
      MetroLine.other(
        slug: "taoyuan_airport_skytrain",
        name: "桃園機場南北側電車",
        name_en: "Taoyuan Airport Skytrain",
        ref: "ST",
        color: COLOR_SKYTRAIN,
        relation_ids: [],
        way_ids: [ 256726319, 256726320 ],
        station_ref_prefix: "ST"
      ),
      MetroLine.other(
        slug: "sun_moon_ropeway",
        name: "九族文化村－日月潭纜車",
        name_en: "Sun Moon Lake Ropeway",
        ref: "SM",
        color: COLOR_ROPEWAY,
        way_ids: [ 65630200 ],
        station_ref_prefix: "SM"
      ),
      MetroLine.other(
        slug: "wulai_trolley",
        name: "烏來台車",
        name_en: "Wulai Trolley",
        ref: "WL",
        color: COLOR_TROLLEY,
        way_ids: WULAI_WAY_IDS,
        station_ref_prefix: "WL"
      ),
      MetroLine.other(
        slug: "alishan_forest_railway",
        name: "阿里山林業鐵路",
        name_en: "Alishan Forest Railway",
        ref: "AF",
        color: COLOR_FOREST_RAILWAY,
        way_ids: ALISHAN_WAY_IDS,
        station_ref_prefix: "AF"
      ),
      MetroLine.other(
        slug: "taipingshan_forest_railway",
        name: "太平山森林鐵路（蹦蹦車）",
        name_en: "Taipingshan Forest Railway",
        ref: "TP",
        color: COLOR_FOREST_RAILWAY,
        way_ids: TAIPINGSHAN_WAY_IDS,
        station_ref_prefix: "TP"
      ),
      MetroLine.other(
        slug: "shengxing_old_mountain_line",
        name: "苗栗舊山線鐵道自行車（勝興段）",
        name_en: "Shengxing Old Mountain Line Rail Bike",
        ref: "OM",
        color: COLOR_RAIL_BIKE,
        way_ids: [ 62123660, 979931899, 62123625, 62123662 ],
        station_ref_prefix: "OM"
      ),
      MetroLine.other(
        slug: "shenao_rail_bike",
        name: "深澳鐵道自行車",
        name_en: "Shen'ao Rail Bike",
        ref: "RB",
        color: COLOR_RAIL_BIKE,
        way_ids: SHENAO_RAIL_BIKE_WAY_IDS,
        station_ref_prefix: "RB"
      ),
      MetroLine.other(
        slug: "jianhushan_ropeway",
        name: "劍湖山世界纜車",
        name_en: "Janfusun Fancyworld Ropeway",
        ref: "JH",
        color: COLOR_ROPEWAY,
        way_ids: [ 1283663642 ],
        station_ref_prefix: "JH"
      ),
      MetroLine.other(
        slug: "eda_ropeway",
        name: "義大纜車",
        name_en: "E-Da Ropeway",
        ref: "ED",
        color: COLOR_ROPEWAY,
        way_ids: [ 969817468 ],
        station_ref_prefix: "ED"
      )
    ].freeze
  end
end
