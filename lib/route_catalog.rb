# frozen_string_literal: true

class RouteCatalog
  METRO_SYSTEM_LABELS = {
    "taipei_metro" => "台北捷運",
    "new_taipei_metro" => "新北捷運",
    "taoyuan_metro" => "桃園捷運",
    "taichung_metro" => "台中捷運",
    "kaohsiung_metro" => "高雄捷運",
    "hsr" => "高鐵",
    "other" => "其他"
  }.freeze

  class << self
    def manifest
      @manifest ||= JSON.parse(Rails.public_path.join("geojson/routes.json").read)
    end

    def find(id)
      manifest.each do |system_id, routes|
        next unless routes.is_a?(Array)

        route = routes.find { |entry| entry["id"] == id }
        return route.merge("system_id" => system_id) if route
      end

      nil
    end

    def find!(id)
      find(id) || raise(ActionController::RoutingError, "Route not found: #{id}")
    end

    def system_label(system_id)
      METRO_SYSTEM_LABELS.fetch(system_id, system_id)
    end
  end
end
