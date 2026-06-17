# frozen_string_literal: true

module Geojson
  module TraCatalog
    BRAND_COLOR = "#004B87".freeze

    BRANCH_SLUGS = %w[
      neiwan_line liujia_line jiji_line pingxi_line chengzhui_line shalun_line shenao_line hualien_port_line taichung_port_line
    ].freeze

    BRANCH_JUNCTION_REFS = {
      "neiwan_line" => %w[1210],
      "liujia_line" => %w[1193],
      "pingxi_line" => %w[7330],
      "chengzhui_line" => %w[3350 2260],
      "pingtung_line" => %w[4400],
      "shalun_line" => %w[4270],
      "shenao_line" => %w[7360],
      "hualien_port_line" => %w[7010],
      "taichung_port_line" => %w[2210]
    }.freeze

    MAIN_LINE_JUNCTION_REFS = {
      "mountain_line" => %w[3350],
      "sea_line" => %w[2260],
      "western_trunk_south" => %w[4400]
    }.freeze

    BRANCH_OF = {
      "neiwan_line" => "mountain_line",
      "liujia_line" => "neiwan_line",
      "jiji_line" => "mountain_line",
      "pingxi_line" => "yilan_line",
      "chengzhui_line" => "mountain_line",
      "shalun_line" => "western_trunk_south",
      "shenao_line" => "yilan_line",
      "hualien_port_line" => "beihui_line",
      "taichung_port_line" => "sea_line"
    }.freeze

    WESTERN_TRUNK_JUNCTION_REF = "3360"
    WESTERN_TRUNK_JUNCTION_NAME = "彰化"
    WESTERN_TRUNK_JUNCTION_LAT = 24.081645713335806
    WESTERN_TRUNK_JUNCTION_LON = 120.53824777629654

    HUALIEN_JUNCTION_REF = "7000"
    HUALIEN_JUNCTION_NAME = "花蓮"
    HUALIEN_JUNCTION_LAT = 23.9927
    HUALIEN_JUNCTION_LON = 121.6009

    GEO_CLIP_BOUNDS = {
      "western_trunk_north" => { min_lat: 24.66 },
      "western_trunk_south" => { max_lat: WESTERN_TRUNK_JUNCTION_LAT + 0.01 }
    }.freeze

    LINES = [
      MetroLine.tra(slug: "western_trunk_north", name: "縱貫線（北段）", name_en: "Western Trunk Line (Northern Section)", ref: "WN", color: BRAND_COLOR, relation_ids: [ 5_867_233 ], station_ref_prefix: "TRA"),
      MetroLine.tra(slug: "mountain_line", name: "山線", name_en: "Mountain Line", ref: "M", color: BRAND_COLOR, relation_ids: [ 5_571_202 ], station_ref_prefix: "TRA"),
      MetroLine.tra(slug: "sea_line", name: "海線", name_en: "Coastal Line", ref: "S", color: BRAND_COLOR, relation_ids: [ 1_827_334 ], station_ref_prefix: "TRA"),
      MetroLine.tra(slug: "western_trunk_south", name: "縱貫線（南段）", name_en: "Western Trunk Line (Southern Section)", ref: "WS", color: BRAND_COLOR, relation_ids: [ 5_867_234 ], station_ref_prefix: "TRA"),
      MetroLine.tra(slug: "pingtung_line", name: "屏東線", name_en: "Pingtung Line", ref: "P", color: BRAND_COLOR, relation_ids: [ 1_827_336 ], station_ref_prefix: "TRA"),
      MetroLine.tra(slug: "south_link", name: "南迴線", name_en: "South Link Line", ref: "SL", color: BRAND_COLOR, relation_ids: [ 5_571_467 ], station_ref_prefix: "TRA"),
      MetroLine.tra(slug: "taidong_line", name: "臺東線", name_en: "Taitung Line", ref: "TD", color: BRAND_COLOR, relation_ids: [ 5_571_509, 20_450_147 ], station_ref_prefix: "TRA"),
      MetroLine.tra(slug: "beihui_line", name: "北迴線", name_en: "North-Link Line", ref: "BH", color: BRAND_COLOR, relation_ids: [ 5_867_230, 5_872_818 ], station_ref_prefix: "TRA"),
      MetroLine.tra(slug: "yilan_line", name: "宜蘭線", name_en: "Yilan Line", ref: "Y", color: BRAND_COLOR, relation_ids: [ 5_867_231, 5_867_232 ], station_ref_prefix: "TRA"),
      MetroLine.tra(slug: "neiwan_line", name: "內灣線", name_en: "Neiwan Line", ref: "NW", color: BRAND_COLOR, relation_ids: [ 5_207_992 ], station_ref_prefix: "TRA", branch_of: BRANCH_OF["neiwan_line"]),
      MetroLine.tra(slug: "liujia_line", name: "六家線", name_en: "Liujia Line", ref: "LJ", color: BRAND_COLOR, relation_ids: [ 5_224_213, 5_224_214 ], station_ref_prefix: "TRA", branch_of: BRANCH_OF["liujia_line"]),
      MetroLine.tra(slug: "jiji_line", name: "集集線", name_en: "Jiji Line", ref: "JJ", color: BRAND_COLOR, relation_ids: [ 5_224_252 ], station_ref_prefix: "TRA", branch_of: BRANCH_OF["jiji_line"]),
      MetroLine.tra(slug: "pingxi_line", name: "平溪線", name_en: "Pingxi Line", ref: "PX", color: BRAND_COLOR, relation_ids: [ 5_149_859 ], station_ref_prefix: "TRA", branch_of: BRANCH_OF["pingxi_line"]),
      MetroLine.tra(slug: "chengzhui_line", name: "成追線", name_en: "Chengzhui Line", ref: "CZ", color: BRAND_COLOR, relation_ids: [ 5_224_215 ], station_ref_prefix: "TRA", branch_of: BRANCH_OF["chengzhui_line"]),
      MetroLine.tra(slug: "shalun_line", name: "沙崙線", name_en: "Shalun Line", ref: "SL", color: BRAND_COLOR, relation_ids: [ 4_252_440, 4_252_441 ], station_ref_prefix: "TRA", branch_of: BRANCH_OF["shalun_line"]),
      MetroLine.tra(slug: "shenao_line", name: "深澳線", name_en: "Shenao Line", ref: "SA", color: BRAND_COLOR, relation_ids: [ 5_149_860 ], station_ref_prefix: "TRA", branch_of: BRANCH_OF["shenao_line"]),
      MetroLine.tra(slug: "hualien_port_line", name: "花蓮臨港線", name_en: "Hualien Port Line", ref: "HP", color: BRAND_COLOR, relation_ids: [ 5_224_251 ], station_ref_prefix: "TRA", branch_of: BRANCH_OF["hualien_port_line"]),
      MetroLine.tra(slug: "taichung_port_line", name: "臺中臨港線", name_en: "Taichung Port Line", ref: "TP", color: BRAND_COLOR, relation_ids: [ 8_969_7472 ], station_ref_prefix: "TRA", branch_of: BRANCH_OF["taichung_port_line"])
    ].freeze
  end
end
