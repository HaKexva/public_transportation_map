# frozen_string_literal: true

module Geojson
  module TaipeiMetroCatalog

    # Same-system in-station transfers (shown as two-color markers).
    # lon/lat: single point between line geometries at the transfer concourse.
    IN_STATION_TRANSFERS_BY_NAME = {
      "大坪林" => { combined_ref: "G04;Y07", lon: 121.5414862, lat: 24.9829263 },
      "七張" => { combined_ref: "G03;G03A", lon: 121.5429203, lat: 24.9750221 },
      "北投" => { combined_ref: "R22;R22A", lon: 121.4985934, lat: 25.1319307 },
      "景安" => { combined_ref: "O02;Y11", lon: 121.5053774, lat: 24.9936008 },
      "頭前庄" => { combined_ref: "O17;Y18", lon: 121.4608616, lat: 25.0397007 },
      "板橋" => {
        combined_ref: "BL07;1020;03",
        lines: %w[bannan],
        lon: 121.462992,
        lat: 25.0144988
      },
      "忠孝復興" => { combined_ref: "BR10;BL15", lon: 121.543333, lat: 25.041389 },
      "中山" => { combined_ref: "R11;G14", lon: 121.5203914, lat: 25.0526256 },
      "松江南京" => { combined_ref: "O08;G15", lon: 121.5330362, lat: 25.0520769 },
      "南京復興" => { combined_ref: "BR11;G16", lon: 121.5439665, lat: 25.0519432 },
      "東門" => { combined_ref: "O06;R07", lon: 121.528611, lat: 25.033611 },
      "古亭" => { combined_ref: "O05;G09", lon: 121.5229975, lat: 25.0264431 },
      "中正紀念堂" => { combined_ref: "R08;G10", lon: 121.5177618, lat: 25.0333942 },
      "大安" => { combined_ref: "BR09;R05", lon: 121.54361, lat: 25.03306 },
      "台北車站" => {
        combined_ref: "R10;BL12;1000;02",
        lines: %w[tamsui_xinyi bannan],
        lon: 121.51702320022838,
        lat: 25.04804218211409
      },
      "南港展覽館" => { combined_ref: "BR24;BL23", lon: 121.6175958, lat: 25.055012 }
    }.freeze

    TRANSFER_STATION_REFS_BY_NAME = IN_STATION_TRANSFERS_BY_NAME.transform_values { |entry| entry[:combined_ref] }.freeze

    LINES = [
      MetroLine.taipei(
        slug: "wenhu_line",
        name: "文湖線",
        name_en: "Wenhu Line",
        ref: "BR",
        color: "#A74C00",
        relation_ids: [ 447449 ],
        station_ref_prefix: "BR"
      ),
      MetroLine.taipei(
        slug: "tamsui_xinyi",
        name: "淡水信義線",
        name_en: "Tamsui–Xinyi Line",
        ref: "R",
        color: "#E3002C",
        relation_ids: [ 5633242 ],
        station_ref_prefix: "R"
      ),
      MetroLine.taipei(
        slug: "xinbeitou_branch",
        name: "新北投支線",
        name_en: "Xinbeitou Branch",
        ref: "R",
        color: "#F890A5",
        relation_ids: [ 2665129 ],
        station_ref_prefix: "R",
        branch_of: "tamsui_xinyi"
      ),
      MetroLine.taipei(
        slug: "bannan",
        name: "板南線",
        name_en: "Bannan Line",
        ref: "BL",
        color: "#007EC7",
        relation_ids: [ 9437776 ],
        station_ref_prefix: "BL"
      ),
      MetroLine.taipei(
        slug: "songshan_xindian",
        name: "松山新店線",
        name_en: "Songshan–Xindian Line",
        ref: "G",
        color: "#008659",
        relation_ids: [ 4250357 ],
        station_ref_prefix: "G"
      ),
      MetroLine.taipei(
        slug: "xiaobitan_branch",
        name: "小碧潭支線",
        name_en: "Xiaobitan Branch",
        ref: "G",
        color: "#CEDC00",
        relation_ids: [ 4250381 ],
        station_ref_prefix: "G",
        branch_of: "songshan_xindian"
      ),
      MetroLine.taipei(
        slug: "zhonghe_xinlu",
        name: "中和新蘆線",
        name_en: "Zhonghe–Xinlu Line",
        ref: "O",
        color: "#F8B61C",
        relation_ids: [ 4250354, 4250355 ],
        station_ref_prefix: "O"
      ),
      MetroLine.taipei(
        slug: "circular",
        name: "環狀線",
        name_en: "Circular Line",
        ref: "Y",
        color: "#FEDB00",
        relation_ids: [ 3322093 ],
        station_ref_prefix: "Y"
      )
    ].freeze
  end
end
