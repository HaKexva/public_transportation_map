# frozen_string_literal: true

module Transit
  # Matches station refs to route manifests using the same conventions as the map UI.
  module StationRef
    TRA_ROUTE_IDS = Geojson::TraCatalog::LINES.map(&:slug).freeze

    module_function

    def matches_route?(station_ref, line_ref:, route_id:, system_id:)
      return false if station_ref.blank?

      sort_key = sort_key_for_route(station_ref, line_ref)
      return false if sort_key.blank?

      if line_ref == "MG" || route_id == "maokong_gondola"
        return sort_key.match?(/^G[1-6]$/i)
      end

      if line_ref == "HSR" || route_id == "taiwan_hsr"
        return sort_key.match?(/^\d{1,3}$/)
      end

      if tra_route?(route_id)
        return sort_key.match?(/^\d{3,4}(-[A-Z]+)?$/)
      end

      # Songshan–Xindian / Xiaobitan use zero-padded G01… refs; bare G1–G6 are Maokong.
      if line_ref == "G"
        return sort_key.match?(/^G\d{2}/i)
      end

      sort_key.match?(/^#{Regexp.escape(line_ref)}\d/i)
    end

    def sort_key_for_route(station_ref, line_ref)
      parts = station_ref.to_s.split(";").map(&:strip).reject(&:empty?)
      return station_ref.to_s if parts.empty?
      return parts.first if line_ref.blank?

      if line_ref == "MG"
        return parts.find { |part| part.match?(/^G\d/i) } || parts.first
      end

      route_part = parts.find { |part| part.match?(/^#{Regexp.escape(line_ref)}\d/i) }
      route_part || parts.first
    end

    def tra_route?(route_id)
      TRA_ROUTE_IDS.include?(route_id)
    end

    def passenger_station?(feature)
      feature_type = feature.dig("properties", "feature_type")
      return true if feature_type == "angle_station"
      return false unless feature_type == "station"

      feature.dig("properties", "passenger_service") != false
    end
  end
end
