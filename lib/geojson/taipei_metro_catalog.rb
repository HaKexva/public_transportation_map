# frozen_string_literal: true

module Geojson
  module TaipeiMetroCatalog
    # Official station codes for the opened Circular Line section (Y07–Y20).
    # Source: New Taipei Metro / Taipei Metro route Y station list.
    CIRCULAR_STATION_REFS_BY_NAME = {
      "大坪林" => "Y07",
      "十四張" => "Y08",
      "秀朗橋" => "Y09",
      "景平" => "Y10",
      "景安" => "Y11",
      "中和" => "Y12",
      "橋和" => "Y13",
      "中原" => "Y14",
      "板新" => "Y15",
      "板橋" => "Y16",
      "新埔民生" => "Y17",
      "頭前庄" => "Y18",
      "幸福" => "Y19",
      "新北產業園區" => "Y20"
    }.freeze

    # Same-system in-station transfers (shown as two-color markers).
    # lon/lat: single point between line geometries at the transfer concourse.
    IN_STATION_TRANSFERS_BY_NAME = {
      "大坪林" => { combined_ref: "G04;Y07", lon: 121.5414862, lat: 24.9829263 },
      "七張" => { combined_ref: "G03;G03A", lon: 121.5429203, lat: 24.9750221 },
      "北投" => { combined_ref: "R22;R22A", lon: 121.4985934, lat: 25.1319307 },
      "景安" => { combined_ref: "O02;Y11", lon: 121.5053774, lat: 24.9936008 },
      "頭前庄" => { combined_ref: "O17;Y18", lon: 121.4608616, lat: 25.0397007 }
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
