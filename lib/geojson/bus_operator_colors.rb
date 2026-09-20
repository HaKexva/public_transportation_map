# frozen_string_literal: true

module Geojson
  # Fixed brand colors for known Taipei / New Taipei bus operators.
  # Unlisted operators keep the importer / recolor hash palette.
  module BusOperatorColors
    NEW_BUS_COLOR = "#6B8F9A" # 新巴士（F 字頭）藍綠灰

    BY_OPERATOR_NAME = {
      "大都會客運" => "#7CB342", # 淺綠
      "首都客運" => "#F97316",   # 橘
      "臺北客運" => "#F97316",   # 北客
      "台北客運" => "#F97316",
      "新店客運" => "#0D9488",   # 藍綠
      "中興巴士" => "#DC2626",   # 中興集團
      "光華巴士" => "#DC2626",
      "淡水客運" => "#DC2626",
      "指南客運" => "#DC2626",
      "東南客運" => "#DB2777",   # 紫紅
      "欣欣客運" => "#9333EA",   # 紫
      "大南汽車" => "#EAB308",   # 黃
      "三重客運" => "#16A34A"    # 綠
    }.freeze

    module_function

    def for_route(ref: nil, name: nil, id: nil)
      return NEW_BUS_COLOR if new_bus_ref?(ref)

      for_operator(name: name, id: id)
    end

    def for_operator(name: nil, id: nil)
      text = name.to_s.strip
      return if text.blank?

      return BY_OPERATOR_NAME[text] if BY_OPERATOR_NAME.key?(text)

      normalized = text.sub(/股份有限公司\z/, "").strip
      BY_OPERATOR_NAME[normalized]
    end

    def new_bus_ref?(ref)
      ref.to_s.strip.match?(/\AF/i)
    end

    def apply_to_geojson!(data)
      properties = data["properties"] || {}
      color = for_route(
        ref: properties["ref"],
        name: properties["operator"],
        id: properties["operator_id"]
      )
      return false unless color
      return false if properties["color"] == color && features_use_color?(data, color)

      properties["color"] = color
      data["properties"] = properties
      Array(data["features"]).each do |feature|
        next unless feature.is_a?(Hash)

        props = feature["properties"] ||= {}
        next unless props.key?("color") || %w[route station].include?(props["feature_type"].to_s)

        props["color"] = color
      end
      true
    end

    def features_use_color?(data, color)
      Array(data["features"]).all? do |feature|
        props = feature.is_a?(Hash) ? feature["properties"] : nil
        next true unless props.is_a?(Hash)
        next true unless props.key?("color") || %w[route station].include?(props["feature_type"].to_s)

        props["color"] == color
      end
    end
    private_class_method :features_use_color?
  end
end
