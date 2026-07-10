# frozen_string_literal: true

class RouteCatalog
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
      I18n.t("systems.#{system_id}", default: system_id)
    end
  end
end
