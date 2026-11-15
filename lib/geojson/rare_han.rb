# frozen_string_literal: true

module Geojson
  # Rare CJK Extension characters that common UI fonts (PingFang / Noto Sans TC)
  # cannot draw. Replace with the everyday form used on local signs / TDX /
  # administrative names so stop labels do not show tofu boxes.
  module RareHan
    # 𫙮 (U+2B66E, Ext. C) — 瑞芳𫙮魚坑; 傑魚里／傑魚坑路 on land-office signs.
    SUBSTITUTIONS = {
      "\u{2B66E}" => "傑"
    }.freeze

    module_function

    def display(text)
      value = text.to_s
      return value if value.empty?

      SUBSTITUTIONS.reduce(value) { |out, (rare, common)| out.gsub(rare, common) }
    end
  end
end
