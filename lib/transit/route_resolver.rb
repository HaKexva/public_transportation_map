# frozen_string_literal: true

module Transit
  class RouteResolver
    def initialize
      @routes_by_system = Hash.new { |hash, key| hash[key] = load_routes(key) }
    end

    def resolve(system_id:, station_refs:)
      refs = station_refs.compact.uniq
      return nil if refs.empty?

      routes = @routes_by_system[system_id]
      return routes.values.first if routes.length == 1

      best_route = nil
      best_score = -1

      routes.each_value do |route|
        route_refs = route.transit_route_stations.pluck(:station_ref)
        score = refs.count { |ref| route_refs.include?(ref) }
        next if score <= best_score

        best_score = score
        best_route = route
      end

      best_route if best_score.positive?
    end

    def find_by_line_ref(system_id:, line_ref:)
      @routes_by_system[system_id].values.find { |route| route.line_ref == line_ref }
    end

    private

    def load_routes(system_id)
      TransitRoute.for_system(system_id).includes(:transit_route_stations).index_by(&:route_id)
    end
  end
end
