# frozen_string_literal: true

module Geojson
  # In-station transfer markers (combined refs) for TRA, HSR, other transit, and cross-system hubs.
  module TransitTransferCatalog
    Entry = Data.define(:combined_ref, :lon, :lat)

    TRA_BRAND_COLOR = Geojson::TraCatalog::BRAND_COLOR

    NAME_ALIASES = {
      "臺北" => "台北",
      "臺南" => "台南",
      "台北車站" => "台北",
      "高鐵臺中站" => "台中",
      "高鐵桃園站" => "桃園",
      "高雄車站" => "高雄"
    }.freeze

    # HSR 左營／台鐵新左營／高雄捷運左營站（12、4340、R16）站內轉乘樞紐。
    ZUOYING_HSR_HUB = {
      tra_ref: "4340",
      tra_lines: %w[western_trunk_south pingtung_line],
      by_system: {
        tra: "4340;12;R16",
        kaohsiung_metro: "R16;4340;12",
        hsr: "12;4340;R16"
      },
      lon: 120.30737341037691,
      lat: 22.687543335422784
    }.freeze

    # HSR 台中／台鐵新烏日／台中捷運高鐵臺中站（07、3340、119）站內轉乘樞紐。
    TAICHUNG_HSR_HUB = {
      tra_ref: "3340",
      tra_lines: %w[mountain_line],
      by_system: {
        tra: "3340;07;119",
        taichung_metro: "119;07;3340",
        hsr: "07;3340;119"
      },
      lon: 120.614252,
      lat: 24.110103
    }.freeze

    # HSR 新竹／台鐵六家（05、1194）站內轉乘樞紐。
    HSINCHU_HSR_HUB = {
      tra_ref: "1194",
      tra_lines: %w[liujia_line],
      by_system: {
        tra: "1194;05",
        hsr: "05;1194"
      },
      lon: 121.03941188336667,
      lat: 24.80711133931995
    }.freeze

    # HSR 台南／台鐵沙崙（11、4272）站內轉乘樞紐。
    TAINAN_HSR_HUB = {
      tra_ref: "4272",
      tra_lines: %w[shalun_line],
      by_system: {
        tra: "4272;11",
        hsr: "11;4272"
      },
      lon: 120.2863739,
      lat: 22.9237208
    }.freeze

    # Cross-system transfers keyed by canonical station name.
    CROSS_SYSTEM = {
      "南港" => {
        tra_ref: "980",
        tra_lines: %w[western_trunk_north],
        by_system: {
          tra: "980;BL22;01",
          taipei_metro: "BL22;980;01",
          hsr: "01;980;BL22"
        },
        lon: 121.6072576,
        lat: 25.0528686
      },
      "松山" => {
        tra_ref: "990",
        tra_lines: %w[western_trunk_north],
        by_system: {
          tra: "990;G19",
          taipei_metro: "G19;990"
        },
        lon: 121.57816703272442,
        lat: 25.04936551944271
      },
      "台北" => {
        tra_ref: "1000",
        tra_lines: %w[western_trunk_north],
        by_system: {
          tra: "1000;R10;BL12;02",
          hsr: "02;1000;R10;BL12"
        },
        lon: 121.51702320022838,
        lat: 25.04804218211409
      },
      "板橋" => {
        tra_ref: "1020",
        tra_lines: %w[western_trunk_north western_trunk_south],
        by_system: {
          tra: "1020;BL07;03",
          hsr: "03;1020;BL07"
        },
        lon: 121.46401388004938,
        lat: 25.013932198858488
      },
      "桃園" => {
        tra_ref: "1080",
        tra_lines: %w[western_trunk_north],
        by_system: {
          taoyuan_metro: "A18;04",
          hsr: "04;A18"
        },
        lon: 121.3137705396601,
        lat: 24.988747268805664
      },
      "六家" => HSINCHU_HSR_HUB,
      "新竹" => HSINCHU_HSR_HUB,
      "新烏日" => TAICHUNG_HSR_HUB.merge(
        lon: 120.61424881953292,
        lat: 24.109753542580645
      ),
      "沙崙" => TAINAN_HSR_HUB,
      "新左營" => ZUOYING_HSR_HUB,
      "左營" => ZUOYING_HSR_HUB,
      "高雄" => {
        tra_ref: "4400",
        tra_lines: %w[pingtung_line western_trunk_south],
        by_system: {
          tra: "4400;R11",
          kaohsiung_metro: "R11;4400"
        },
        lon: 120.3025585,
        lat: 22.6395321
      },
      "動物園" => {
        by_system: {
          other: "G1;BR01",
          taipei_metro: "BR01;G1"
        },
        lon: 121.5762884,
        lat: 24.9959573
      }
    }.freeze

    # Do not show in-station transfers for TRA branch lines.

    class << self
      def transfer_for(name, line:, ref: nil)
        canonical = canonical_name(name)
        return nil if canonical.blank?

        cross_system_for(canonical, line:, ref: ref)
      end

      def apply_tra_transfers!(stations, line:)
        stations.map do |station|
          entry = transfer_for(station[:name], line: line, ref: station[:ref])
          next station unless entry

          station.merge(
            ref: ref_for_line(entry.combined_ref, line: line),
            lon: entry.lon || station[:lon],
            lat: entry.lat || station[:lat]
          )
        end
      end

      def ref_for_line(combined_ref, line:)
        parts = combined_ref.to_s.split(";").map(&:strip)
        return combined_ref if parts.length <= 1
        return combined_ref if cross_system_transfer_parts?(parts)
        return combined_ref unless line.system_id == "tra"

        suffix = line.ref.to_s
        line_specific = parts.find { |part| part.match?(/\A\d+-#{Regexp.escape(suffix)}\z/) }
        return line_specific if line_specific

        parts.find { |part| part.match?(/\A\d+\z/) } || parts.first
      end

      def canonical_name(name)
        normalized = name.to_s.strip.sub(/車站\z/, "")
        return nil if normalized.blank?

        canonical = NAME_ALIASES[normalized] || normalized
        case canonical
        when "臺北" then "台北"
        when "臺南" then "台南"
        else canonical
        end
      end

      private

      def canonical_tra_ref(ref)
        ref.to_s.split(";").first.to_s.sub(/-.*\z/, "")
      end

      def cross_system_transfer_parts?(parts)
        tra_part = parts.any? { |part| part.match?(/\A\d{3,4}(-[A-Z]+)?\z/) }
        other_part = parts.any? { |part| part.match?(/\A[A-Z]{1,3}\d/i) || part.match?(/\A\d{2}\z/) }

        tra_part && other_part
      end

      def cross_system_for(canonical, line:, ref: nil)
        entry = CROSS_SYSTEM[canonical]
        entry ||= TAICHUNG_HSR_HUB if canonical == "台中" && line.system_id.in?(%w[hsr taichung_metro])
        entry ||= ZUOYING_HSR_HUB if canonical == "左營" && line.system_id.in?(%w[hsr kaohsiung_metro])
        entry ||= TAINAN_HSR_HUB if canonical == "台南" && line.system_id == "hsr"
        entry ||= HSINCHU_HSR_HUB if canonical == "新竹" && line.system_id == "hsr"
        return nil unless entry

        if line.system_id == "tra"
          return nil unless entry[:tra_lines]&.include?(line.slug)
          return nil if entry[:tra_ref] && ref.present? && canonical_tra_ref(ref) != entry[:tra_ref]

          combined_ref = entry.dig(:by_system, :tra)
          return nil unless combined_ref

          return Entry.new(combined_ref: combined_ref, lon: entry[:lon], lat: entry[:lat])
        end

        system_key = line.system_id.to_sym
        combined_ref = entry.dig(:by_system, system_key)
        return nil unless combined_ref

        Entry.new(combined_ref: combined_ref, lon: entry[:lon], lat: entry[:lat])
      end
    end
  end
end
