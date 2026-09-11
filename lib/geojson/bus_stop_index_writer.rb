# frozen_string_literal: true

require "fileutils"
require "json"

module Geojson
  # Inverts bus GeoJSON stop poles into StationID / lat-lon cluster → routes.
  # Written per city folder as `_stop_routes.json` for lazy map popup lookup.
  class BusStopIndexWriter
    INDEX_FILENAME = "_stop_routes.json"

    Result = Data.define(:cities, :stations, :clusters)

    def self.write!(bus_root: nil)
      new(bus_root: bus_root).write!
    end

    def self.index_path_for(subdir, bus_root: nil)
      root = bus_root || Geojson::BusLayout.bus_root
      root.join(subdir, INDEX_FILENAME)
    end

    def initialize(bus_root: nil)
      @bus_root = bus_root || Geojson::BusLayout.bus_root
    end

    def write!
      by_subdir = Hash.new { |hash, key|
        hash[key] = { "stations" => {}, "clusters" => {} }
      }

      Dir.glob(@bus_root.join("**/*.geojson")).sort.each do |path|
        next if File.basename(path).start_with?("_")

        data = JSON.parse(File.read(path))
        properties = data["properties"] || {}
        route_id = properties["id"].presence || File.basename(path, ".geojson")
        city_id = properties["city_id"].presence || Geojson::BusLayout.city_id_for_slug(route_id)
        subdir = Geojson::BusLayout.subdir_for(city_id) || relative_subdir(path)
        next if subdir.blank?

        route = Geojson::BusStopClustering.route_entry(
          "id" => route_id,
          "ref" => properties["ref"],
          "name" => properties["name"].presence || properties["ref"] || route_id,
          "color" => properties["color"]
        )

        Array(data["features"]).each do |feature|
          props = feature["properties"] || {}
          next unless props["feature_type"] == "station"

          lon, lat = Geojson::BusStopClustering.coordinates_for(feature)
          name = props["name"].to_s
          station_id = Geojson::BusStopClustering.station_id_for(props)
          cluster = Geojson::BusStopClustering.cluster_key(name:, lon:, lat:)

          city_index = by_subdir[subdir]
          if station_id.present?
            city_index["stations"][station_id] ||= []
            Geojson::BusStopClustering.merge_route!(city_index["stations"][station_id], route)
          end
          if cluster.present?
            city_index["clusters"][cluster] ||= []
            Geojson::BusStopClustering.merge_route!(city_index["clusters"][cluster], route)
          end
        end
      rescue JSON::ParserError
        next
      end

      stations = 0
      clusters = 0
      by_subdir.each do |subdir, payload|
        stations += payload["stations"].size
        clusters += payload["clusters"].size
        sort_routes!(payload)
        path = self.class.index_path_for(subdir, bus_root: @bus_root)
        FileUtils.mkdir_p(path.dirname)
        File.write(path, "#{JSON.pretty_generate(payload)}\n")
        puts "Wrote #{path}"
      end

      Result.new(cities: by_subdir.keys.sort, stations:, clusters:)
    end

    private

    def relative_subdir(path)
      relative = Pathname.new(path).relative_path_from(@bus_root)
      relative.each_filename.first
    rescue ArgumentError
      nil
    end

    def sort_routes!(payload)
      payload["stations"].each_value { |routes| routes.sort_by! { |row| [ row["ref"].to_s, row["id"].to_s ] } }
      payload["clusters"].each_value { |routes| routes.sort_by! { |row| [ row["ref"].to_s, row["id"].to_s ] } }
    end
  end
end
