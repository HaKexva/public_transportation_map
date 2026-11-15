# frozen_string_literal: true

module Transit
  # Bus make / model by operator and plate series (config/bus_vehicle_models.yml).
  # No official feed publishes models, so this table is maintained by hand;
  # `bin/rails transit:bus_fleet_series` lists the series still missing.
  module BusVehicleModels
    PATH = Rails.root.join("config/bus_vehicle_models.yml")

    module_function

    def lookup(plate, operator_id = nil, city_id = nil)
      plate = plate.to_s.upcase
      return nil if plate.empty?

      match = entries.select { |entry| entry[:operator_ids].empty? || entry[:operator_ids].include?(operator_id.to_s) }
        .select { |entry| entry[:city_ids].empty? || entry[:city_ids].include?(city_id.to_s) }
        .flat_map { |entry| entry[:plates].map { |pattern| [ pattern, entry[:model] ] } }
        .select { |pattern, _model| matches?(plate, pattern) }
        .max_by { |pattern, _model| pattern.length }
      match&.last
    end

    # "EAL-" matches EAL-0123, "-U3" matches 845-U3, a full plate matches itself.
    def matches?(plate, pattern)
      if pattern.start_with?("-") then plate.end_with?(pattern)
      elsif pattern.end_with?("-") then plate.start_with?(pattern)
      else plate == pattern || plate.start_with?(pattern)
      end
    end

    # Letter part that groups one registration batch: "EAL-" or "-U3".
    def series(plate)
      head, tail = plate.to_s.upcase.split("-", 2)
      return nil unless tail

      head.match?(/\A\d+\z/) ? "-#{tail}" : "#{head}-"
    end

    def entries
      @entries = nil if Rails.env.development?
      @entries ||= load_entries
    end

    def entries=(list)
      @entries = list&.map { |entry| normalize(entry) }
    end

    def load_entries
      return [] unless PATH.exist?

      Array(YAML.safe_load_file(PATH)&.dig("models")).map { |entry| normalize(entry) }
    end

    def normalize(entry)
      entry = entry.to_h.transform_keys(&:to_s)
      {
        model: entry["model"].to_s.strip,
        operator_ids: Array(entry["operator_id"] || entry["operator_ids"]).map(&:to_s),
        city_ids: Array(entry["city_id"] || entry["city_ids"]).map(&:to_s),
        plates: Array(entry["plates"]).map { |plate| plate.to_s.upcase.strip }.reject(&:empty?)
      }
    end
  end
end
