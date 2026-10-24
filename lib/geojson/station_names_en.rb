# frozen_string_literal: true

module Geojson
  # English names for rail / ferry / cable-car stations, keyed by the Chinese
  # station name. Seeded from OpenStreetMap name:en (see `generate!`) and
  # hand-editable in config/station_names_en.yml; builders and `apply!` copy
  # them onto station features as name_en.
  module StationNamesEn
    PATH = Rails.root.join("config/station_names_en.yml")
    OSM_EXTRACT = Rails.root.join("tmp/osm/stations.geojsonseq")
    SYSTEM_DIRS = %w[taipei_metro new_taipei_metro taoyuan_metro taichung_metro kaohsiung_metro hsr tra sugar_railway ferry other].freeze
    STATION_TYPES = %w[station angle_station].freeze
    MAX_MATCH_METERS = 3_000

    module_function

    def dictionary
      @dictionary ||= PATH.exist? ? (YAML.load_file(PATH) || {}) : {}
    end

    def reload!
      @dictionary = nil
    end

    def lookup(name)
      return if name.blank?

      dictionary[name.to_s] || dictionary[normalize(name)]
    end

    def normalize(name)
      name.to_s.tr("臺", "台").gsub(/[\s　]/, "").sub(/[（(].*[)）]\z/, "").sub(/(火車站|車站|站)\z/, "")
    end

    def station_features(root: Rails.root.join("public/geojson"))
      SYSTEM_DIRS.flat_map { |dir| Dir.glob(root.join(dir, "**/*.geojson")) }.flat_map do |path|
        Array(JSON.parse(File.read(path))["features"]).select do |feature|
          STATION_TYPES.include?(feature.dig("properties", "feature_type")) && feature.dig("geometry", "type") == "Point"
        end
      end
    end

    # Matches every station name in the map to the nearest same-named OSM
    # feature carrying name:en. Existing entries win, so hand fixes survive.
    def generate!(root: Rails.root.join("public/geojson"), extract: OSM_EXTRACT)
      osm = Hash.new { |hash, key| hash[key] = [] }
      File.foreach(extract) do |line|
        feature = JSON.parse(line.delete_prefix("\u001e"))
        tags = feature["properties"] || {}
        english = tags["name:en"].to_s.strip
        next if english.empty? || english.match?(/\p{Han}/)

        point = representative_point(feature["geometry"])
        next unless point

        [ tags["name"], tags["name:zh"], tags["name:zh-Hant"], tags["official_name"] ].compact.uniq.each do |zh|
          osm[normalize(zh)] << { point:, english:, rail: tags.key?("railway") || tags.key?("station") || tags.key?("aerialway") || tags["amenity"] == "ferry_terminal" }
        end
      end

      found = {}
      missing = []
      station_features(root:).each do |feature|
        name = feature.dig("properties", "name").to_s
        next if name.empty? || dictionary.key?(name) || found.key?(name)

        point = feature.dig("geometry", "coordinates")
        best = osm[normalize(name)].min_by { |candidate| [ candidate[:rail] ? 0 : 1, meters(point, candidate[:point]) ] }
        if best && meters(point, best[:point]) <= MAX_MATCH_METERS
          found[name] = best[:english]
        else
          missing << name
        end
      end

      merged = dictionary.merge(found).sort.to_h
      File.write(PATH, merged.to_yaml(line_width: -1))
      reload!
      { added: found.size, missing: missing.uniq }
    end

    def apply!(root: Rails.root.join("public/geojson"))
      changed = 0
      SYSTEM_DIRS.flat_map { |dir| Dir.glob(root.join(dir, "**/*.geojson")) }.each do |path|
        data = JSON.parse(File.read(path))
        dirty = false
        Array(data["features"]).each do |feature|
          properties = feature["properties"] || {}
          next unless STATION_TYPES.include?(properties["feature_type"])

          english = lookup(properties["name"])
          next if english.blank? || properties["name_en"] == english

          properties["name_en"] = english
          dirty = true
        end
        next unless dirty

        File.write(path, JSON.pretty_generate(data) + "\n")
        changed += 1
      end
      changed
    end

    def representative_point(geometry)
      return unless geometry

      case geometry["type"]
      when "Point" then geometry["coordinates"]
      else
        points = geometry["coordinates"].flatten.each_slice(2).to_a
        points.empty? ? nil : [ points.sum(&:first) / points.size, points.sum(&:last) / points.size ]
      end
    end

    def meters(a, b)
      lat = (a[1] + b[1]) / 2.0 * Math::PI / 180
      dx = (a[0] - b[0]) * 111_320 * Math.cos(lat)
      dy = (a[1] - b[1]) * 110_540
      Math.sqrt(dx * dx + dy * dy)
    end
  end
end
