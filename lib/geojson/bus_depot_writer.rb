# frozen_string_literal: true

require "fileutils"
require "json"

module Geojson
  # Aggregates bus dispatch yards / operator parking poles into a depot catalog.
  class BusDepotWriter
    OUTPUT_PATH = Rails.root.join("public/geojson/bus_depots.json")
    # ~1.1 km grid: opposite-direction poles and nearby yard gates merge.
    COORD_DECIMALS = 2

    Result = Data.define(:depots)

    def self.write!(path: OUTPUT_PATH, bus_root: nil)
      new(path: path, bus_root: bus_root).write!
    end

    def initialize(path:, bus_root: nil)
      @path = path
      @bus_root = bus_root || Geojson::BusLayout.bus_root
    end

    def write!
      buckets = Hash.new { |hash, key|
        hash[key] = {
          "name" => nil,
          "routes" => [],
          "lons" => [],
          "lats" => [],
          "station_ids" => []
        }
      }

      Dir.glob(@bus_root.join("**/*.geojson")).sort.each do |path|
        next if File.basename(path).start_with?("_")

        data = JSON.parse(File.read(path))
        properties = data["properties"] || {}
        route_id = properties["id"].presence || File.basename(path, ".geojson")

        Array(data["features"]).each do |feature|
          props = feature["properties"] || {}
          next unless props["feature_type"] == "station"
          next unless depot_feature?(props)

          lon, lat = Geojson::BusStopClustering.coordinates_for(feature)
          next if lon.nil? || lat.nil?

          name = props["name"].to_s
          station_id = Geojson::BusStopClustering.station_id_for(props)
          key = depot_bucket_key(name:, lon:, lat:, station_id:)
          next if key.blank?

          bucket = buckets[key]
          bucket["name"] ||= name
          bucket["lons"] << lon
          bucket["lats"] << lat
          bucket["station_ids"] << station_id if station_id.present?
          bucket["routes"] << route_id unless bucket["routes"].include?(route_id)
        end
      rescue JSON::ParserError
        next
      end

      depots = buckets.filter_map do |key, bucket|
        next if bucket["routes"].empty?

        lon = average(bucket["lons"])
        lat = average(bucket["lats"])
        next if lon.nil? || lat.nil?

        id = "bus_depot_#{key}".gsub(/[^\w.-]+/, "_").squeeze("_")

        {
          "id" => id,
          "name" => bucket["name"],
          "routes" => bucket["routes"].sort,
          "lon" => lon.round(6),
          "lat" => lat.round(6),
          "station_ids" => bucket["station_ids"].uniq.sort,
          "grade" => "調度站"
        }.compact
      end.sort_by { |depot| [ depot["name"].to_s, depot["id"].to_s ] }

      FileUtils.mkdir_p(@path.dirname)
      File.write(@path, "#{JSON.pretty_generate(depots)}\n")
      puts "Wrote #{@path} (#{depots.length} bus depots)"
      Result.new(depots: depots)
    end

    private

    def depot_feature?(properties)
      return true if properties["stop_role"].to_s == "depot" || properties[:stop_role].to_s == "depot"

      Geojson::BusImporter.depot_stop_name?(properties["name"] || properties[:name])
    end

    def depot_bucket_key(name:, lon:, lat:, station_id:)
      return "sid:#{station_id}" if station_id.present?
      return nil if name.blank?

      lat_key = format("%.#{COORD_DECIMALS}f", lat.to_f)
      lon_key = format("%.#{COORD_DECIMALS}f", lon.to_f)
      "#{lat_key}|#{lon_key}|#{name}"
    end

    def average(values)
      list = Array(values).compact
      return nil if list.empty?

      list.sum.to_f / list.length
    end
  end
end
