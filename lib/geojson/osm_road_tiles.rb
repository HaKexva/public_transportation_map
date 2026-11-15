# frozen_string_literal: true

module Geojson
  # Drivable OSM roads cut into small square tiles so bus shapes can be checked
  # and re-routed against the real street network without loading all of Taiwan.
  #
  # Build once from a Geofabrik extract (needs osmium-tool):
  #   bin/rails geojson:osm_road_tiles
  module OsmRoadTiles
    TILE_DEGREES = 0.02
    SOURCE_URL = "https://download.geofabrik.de/asia/taiwan-latest.osm.pbf"
    HIGHWAYS = %w[
      motorway motorway_link trunk trunk_link primary primary_link secondary secondary_link
      tertiary tertiary_link unclassified residential living_street service busway bus_guideway road
    ].freeze
    # Routing cost multipliers: prefer real streets over aisles and private lots,
    # but keep those usable (bus terminals are often private service roads).
    SERVICE_COST = { "parking_aisle" => 1.5, "driveway" => 2.0 }.freeze
    DEFAULT_SERVICE_COST = 1.3
    PRIVATE_COST = 2.0

    module_function

    def root
      Rails.root.join("tmp/osm")
    end

    def tiles_dir
      root.join("road_tiles")
    end

    def available?
      tiles_dir.exist? && tiles_dir.children.any?
    end

    def tile_key(lon, lat)
      "#{(lon / TILE_DEGREES).floor}_#{(lat / TILE_DEGREES).floor}"
    end

    def tile_keys_for_bbox(min_lon, min_lat, max_lon, max_lat)
      xs = ((min_lon / TILE_DEGREES).floor..(max_lon / TILE_DEGREES).floor)
      ys = ((min_lat / TILE_DEGREES).floor..(max_lat / TILE_DEGREES).floor)
      xs.flat_map { |x| ys.map { |y| "#{x}_#{y}" } }
    end

    # Ways as { "c" => coords, "o" => 1 | -1 | 0 (oneway), "k" => cost multiplier, "n" => name (optional) }.
    def load_tile(key)
      path = tiles_dir.join("#{key}.json")
      path.exist? ? JSON.parse(File.read(path)) : []
    end

    def build!(source: root.join("taiwan-latest.osm.pbf"))
      FileUtils.mkdir_p(root)
      download!(source) unless File.exist?(source)
      roads_pbf = root.join("roads.osm.pbf")
      roads_seq = root.join("roads.geojsonseq")
      run!("osmium", "tags-filter", source.to_s, "w/highway=#{HIGHWAYS.join(',')}", "-o", roads_pbf.to_s, "--overwrite")
      run!("osmium", "export", roads_pbf.to_s, "-f", "geojsonseq", "--geometry-types=linestring", "-o", roads_seq.to_s, "--overwrite")

      tiles = Hash.new { |hash, key| hash[key] = [] }
      File.foreach(roads_seq) do |line|
        feature = JSON.parse(line.delete_prefix("\u001E"))
        coords = feature.dig("geometry", "coordinates")
        next unless coords.is_a?(Array) && coords.length >= 2

        tags = feature["properties"] || {}
        next unless HIGHWAYS.include?(tags["highway"])

        way = { "c" => coords.map { |lon, lat| [ lon.round(7), lat.round(7) ] }, "o" => oneway(tags), "k" => cost(tags) }
        way["n"] = tags["name"] if tags["name"].present?
        lons = coords.map(&:first)
        lats = coords.map(&:last)
        tile_keys_for_bbox(lons.min, lats.min, lons.max, lats.max).each { |key| tiles[key] << way }
      end

      FileUtils.rm_rf(tiles_dir)
      FileUtils.mkdir_p(tiles_dir)
      tiles.each { |key, ways| File.write(tiles_dir.join("#{key}.json"), JSON.generate(ways)) }
      tiles.length
    end

    def oneway(tags)
      return 0 if %w[no].include?(tags["oneway:bus"]) || %w[no].include?(tags["oneway:psv"])

      case tags["oneway"]
      when "yes", "true", "1" then 1
      when "-1", "reverse" then -1
      when "no", "false", "0" then 0
      else
        return 1 if %w[roundabout circular].include?(tags["junction"])
        return 1 if %w[motorway motorway_link].include?(tags["highway"])

        0
      end
    end

    def cost(tags)
      multiplier = 1.0
      multiplier = SERVICE_COST.fetch(tags["service"], DEFAULT_SERVICE_COST) if tags["highway"] == "service"
      multiplier = 1.2 if tags["highway"] == "living_street"
      bus_allowed = %w[yes designated permissive].include?(tags["bus"]) || %w[yes designated permissive].include?(tags["psv"])
      multiplier *= PRIVATE_COST if %w[private no].include?(tags["access"]) && !bus_allowed
      multiplier
    end

    def download!(target)
      run!("curl", "-sSL", "-o", target.to_s, SOURCE_URL)
    end

    def run!(*command)
      system(*command, exception: true)
    end
  end
end
