# frozen_string_literal: true

module Transit
  module MetroSystemRegistry
    Entry = Data.define(:tdx_rail_system, :system_id, :line_map)

    ENTRIES = [
      Entry.new(
        tdx_rail_system: "TRTC",
        system_id: "taipei_metro",
        line_map: {
          "BR" => "wenhu_line",
          "R" => "tamsui_xinyi",
          "BL" => "bannan",
          "G" => "songshan_xindian",
          "O" => "zhonghe_xinlu",
          "Y" => "circular"
        }
      ),
      Entry.new(
        tdx_rail_system: "NTMC",
        system_id: "new_taipei_metro",
        line_map: {
          "V" => "danhai_lrt",
          "K" => "ankeng_lrt",
          "LB" => "sanying_line"
        }
      ),
      Entry.new(
        tdx_rail_system: "NTDLRT",
        system_id: "new_taipei_metro",
        line_map: { "V" => "danhai_lrt" }
      ),
      Entry.new(
        tdx_rail_system: "NTALRT",
        system_id: "new_taipei_metro",
        line_map: { "K" => "ankeng_lrt" }
      ),
      Entry.new(
        tdx_rail_system: "TYMC",
        system_id: "taoyuan_metro",
        line_map: {
          "A" => "airport_mrt",
          "C" => "circular_lrt"
        }
      ),
      Entry.new(
        tdx_rail_system: "KRTC",
        system_id: "kaohsiung_metro",
        line_map: {
          "R" => "red_line",
          "O" => "orange_line",
          "C" => "circular"
        }
      ),
      Entry.new(
        tdx_rail_system: "KLRT",
        system_id: "kaohsiung_metro",
        line_map: { "C" => "circular_lrt" }
      ),
      Entry.new(
        tdx_rail_system: "TMRT",
        system_id: "taichung_metro",
        line_map: { "1" => "green_line" }
      )
    ].freeze

    module_function

    def entries
      ENTRIES
    end

    def route_id_for(tdx_rail_system:, line_id:)
      entry = ENTRIES.find { |item| item.tdx_rail_system == tdx_rail_system }
      return nil unless entry

      entry.line_map[line_id.to_s] || entry.line_map[line_id.to_s.upcase]
    end
  end
end
