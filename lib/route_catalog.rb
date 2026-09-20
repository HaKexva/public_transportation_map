# frozen_string_literal: true

class RouteCatalog
  class << self
    def manifest
      if Rails.env.development?
        load_manifest
      else
        @manifest ||= load_manifest
      end
    end

    def reset!
      @manifest = nil
    end

    def manifest_path
      Rails.public_path.join("geojson/routes.json")
    end

    def bus_manifest_path
      Rails.public_path.join("geojson/bus/manifest.json")
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

    private

    def load_manifest
      payload = JSON.parse(manifest_path.read)
      bus_path = bus_manifest_path
      if bus_path.exist?
        bus_payload = JSON.parse(bus_path.read)
        buses = bus_payload.is_a?(Hash) ? bus_payload.fetch("bus", []) : Array(bus_payload)
        payload["bus"] = buses if buses.any?
      elsif !payload.key?("bus")
        payload["bus"] = []
      end
      payload
    end
  end
end
