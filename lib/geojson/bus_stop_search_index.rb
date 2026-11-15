# frozen_string_literal: true

require "fileutils"
require "json"

module Geojson
  # Compact name → position catalog for sidebar stop search.
  # One row per stop group in the city `_stop_routes.json` files.
  class BusStopSearchIndex
    FILENAME = "_stop_search.json"

    # TDX StopUID prefixes. Taipei and New Taipei share one folder, so the
    # prefix is what tells a pole's arrivals API apart.
    UID_CITY = {
      "TPE" => "Taipei",
      "NWT" => "NewTaipei",
      "KEE" => "Keelung",
      "TAO" => "Taoyuan",
      "HSZ" => "Hsinchu",
      "HSQ" => "HsinchuCounty",
      "MIA" => "MiaoliCounty",
      "TXG" => "Taichung",
      "CHA" => "ChanghuaCounty",
      "NAN" => "NantouCounty",
      "YUN" => "YunlinCounty",
      "CYI" => "Chiayi",
      "CYQ" => "ChiayiCounty",
      "TNN" => "Tainan",
      "KHH" => "Kaohsiung",
      "PIF" => "PingtungCounty",
      "ILA" => "YilanCounty",
      "HUA" => "HualienCounty",
      "TTT" => "TaitungCounty",
      "PEN" => "PenghuCounty",
      "KIN" => "KinmenCounty",
      "THB" => "InterCity"
    }.freeze

    def self.path(bus_root: nil)
      (bus_root || Geojson::BusLayout.bus_root).join(FILENAME)
    end

    def self.write!(bus_root: nil)
      root = bus_root || Geojson::BusLayout.bus_root
      by_subdir = {}
      Dir.glob(root.join("**/#{Geojson::BusStopIndexWriter::INDEX_FILENAME}")).sort.each do |file|
        subdir = Pathname.new(file).relative_path_from(root).each_filename.first
        by_subdir[subdir] = JSON.parse(File.read(file))
      rescue JSON::ParserError
        next
      end
      write_groups!(by_subdir, bus_root: root)
    end

    # `by_subdir` values are stop-index payloads (`groups` plus route lists).
    def self.write_groups!(by_subdir, bus_root: nil)
      new(by_subdir, bus_root: bus_root).write!
    end

    def initialize(by_subdir, bus_root: nil)
      @by_subdir = by_subdir || {}
      @bus_root = bus_root || Geojson::BusLayout.bus_root
    end

    def write!
      stops = []
      @by_subdir.each do |subdir, payload|
        groups = payload.is_a?(Hash) ? payload["groups"] : nil
        next unless groups.is_a?(Hash)

        groups.each do |key, group|
          # Absorbed into a city shelter — keep one search hit with both UIDs.
          next if group.is_a?(Hash) && group["shelter_of"]

          row = row_for(subdir, key, group)
          stops << row if row
        end
      end
      stops.sort_by! { |row| [ row[0].to_s, row[4].to_s ] }

      path = self.class.path(bus_root: @bus_root)
      FileUtils.mkdir_p(path.dirname)
      File.write(path, JSON.generate("stops" => stops))
      path
    end

    private

    # [name, name_en, lat, lon, group_id, platform, platform_en, road, road_en, toward, toward_en, stop_uid, cities]
    def row_for(subdir, key, group)
      return unless group.is_a?(Hash)

      name = group["name"].to_s
      lat = group["lat"]
      lon = group["lon"]
      return if name.blank? || !lat.is_a?(Numeric) || !lon.is_a?(Numeric)

      uids = Array(group["stops"]).map(&:to_s).reject(&:blank?)
      cities = cities_for(subdir, uids)
      return if cities.empty?

      primary = cities.first
      stop_uid = uids.find { |uid| UID_CITY[uid[0, 3]] == primary } || uids.first.to_s
      [
        name,
        group["name_en"].to_s,
        lat,
        lon,
        key.to_s,
        group["platform"].to_s,
        group["platform_en"].to_s,
        group["road"].to_s,
        group["road_en"].to_s,
        group["toward"].to_s,
        group["toward_en"].to_s,
        stop_uid,
        cities
      ]
    end

    def cities_for(subdir, uids)
      tally = Hash.new(0)
      uids.each do |uid|
        city = UID_CITY[uid[0, 3]]
        tally[city] += 1 if city
      end
      return tally.sort_by { |_city, count| -count }.map(&:first) if tally.any?

      city = sole_city_for(subdir)
      city ? [ city ] : []
    end

    def sole_city_for(subdir)
      cities = Geojson::BusLayout::CITY_SUBDIRS.select { |_id, dir| dir == subdir }.keys
      cities.first if cities.one?
    end
  end
end
