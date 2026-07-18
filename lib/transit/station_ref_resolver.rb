# frozen_string_literal: true

module Transit
  class StationRefResolver
    HSR_TDX_TO_REF = {
      "0990" => "01",
      "1000" => "02",
      "1010" => "03",
      "1020" => "04",
      "1030" => "05",
      "1035" => "06",
      "1040" => "07",
      "1043" => "08",
      "1047" => "09",
      "1050" => "10",
      "1060" => "11",
      "1070" => "12"
    }.freeze

    def initialize
      @by_system = Hash.new { |hash, key| hash[key] = build_system_index(key) }
    end

    def resolve(system_id:, tdx_station_id:, line_ref: nil, station_name: nil)
      tdx_id = tdx_station_id.to_s.strip
      return nil if tdx_id.blank?

      if system_id == "hsr"
        ref = HSR_TDX_TO_REF[tdx_id]
        return find_route_station("hsr", ref) if ref
      end

      index = @by_system[system_id]
      return index[:by_tdx_id][tdx_id] if index[:by_tdx_id].key?(tdx_id)

      if line_ref.present?
        prefixed = "#{line_ref}#{tdx_id}"
        return index[:by_ref][prefixed] if index[:by_ref].key?(prefixed)
      end

      if station_name.present?
        normalized = normalize_name(station_name)
        return index[:by_name][normalized] if index[:by_name].key?(normalized)
      end

      index[:by_ref].values.find { |station| station.station_ref.split(";").include?(tdx_id) }
    end

    def resolve_ref(system_id:, tdx_station_id:, **kwargs)
      resolve(system_id: system_id, tdx_station_id: tdx_station_id, **kwargs)&.station_ref
    end

    private

    def build_system_index(system_id)
      stations = TransitRouteStation.joins(:transit_route).where(transit_routes: { system_id: system_id })

      {
        by_tdx_id: {},
        by_ref: stations.index_by(&:station_ref),
        by_name: stations.index_by { |station| normalize_name(station.name) }
      }.tap do |index|
        stations.each do |station|
          station.station_ref.split(";").each do |part|
            part = part.strip
            index[:by_tdx_id][part] ||= station
          end
        end
      end
    end

    def find_route_station(system_id, ref)
      @by_system[system_id][:by_ref].values.find { |station| station.station_ref.start_with?("#{ref};") || station.station_ref == ref }
    end

    def normalize_name(name)
      name.to_s.gsub(/臺/, "台").strip
    end
  end
end
