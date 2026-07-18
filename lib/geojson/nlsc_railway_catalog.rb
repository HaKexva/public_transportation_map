# frozen_string_literal: true

require "json"
require "fileutils"
require "net/http"
require "uri"
require "shellwords"

module Geojson
  # Railway centerlines from NLSC open data (same source as 台灣通用電子地圖).
  module NlscRailwayCatalog
    CACHE_DIR = Rails.root.join("lib/geojson/fallback_tracks/nlsc_railways")
    DEPOT_CACHE_DIR = Rails.root.join("lib/geojson/fallback_tracks/nlsc_depot_spurs")

    DATASETS = {
      tra: {
        url: "https://opdadm.moi.gov.tw/api/v1/no-auth/resource/api/dataset/299841E1-714A-40BA-AF4B-D6527EEA2A41/resource/801DECA5-E75E-40A4-816C-1BD6A1F322C9/download",
        zip: "tra_rail.zip"
      },
      hsr: {
        url: "https://www.tgos.tw/tgos/VirtualDir/Product/db6bff0a-58a5-40c1-81fb-ac8312213784/HSRAIL_1130417.zip",
        zip: "hsr_rail.zip"
      },
      mrt: {
        url: "https://opdadm.moi.gov.tw/api/v1/no-auth/resource/api/dataset/159E4D93-A053-4382-A6BD-9DE6B5C4E19F/resource/9D9CF5D4-EEA3-4E1C-ACB0-ECDBBA27C713/download",
        zip: "mrt_rail.zip"
      }
    }.freeze

    DEPOT_DATASET_KEYS = {
      /^(tra)_/ => :tra,
      /^(hsr)_/ => :hsr
    }.freeze

    def self.dataset_key_for_depot(depot)
      id = depot[:id].to_s
      return :hsr if id.start_with?("hsr_")
      return :tra if id.start_with?("tra_")
      :mrt
    end

    def self.spur_lines_near_depot(depot, radius_m: 2_000)
      dataset_key = dataset_key_for_depot(depot)
      lines = line_strings_for_dataset(dataset_key)
      return [] if lines.empty?

      lon = depot[:lon]
      lat = depot[:lat]
      max_delta = radius_m / 111_000.0

      lines.select do |line|
        line.any? do |point_lon, point_lat|
          (point_lon - lon).abs <= max_delta && (point_lat - lat).abs <= max_delta
        end
      end
    end

    def self.line_strings_for_depot(depot_id)
      cache_path = DEPOT_CACHE_DIR.join("#{depot_id}.json")
      return [] unless cache_path.exist?

      JSON.parse(cache_path.read).fetch("line_strings", [])
    end

    def self.refresh_depot_cache!(depot, radius_m: 2_000)
      lines = spur_lines_near_depot(depot, radius_m: radius_m)
      return false if lines.empty?

      FileUtils.mkdir_p(DEPOT_CACHE_DIR)
      payload = {
        depot_id: depot[:id],
        source: "nlsc_open_data",
        dataset: dataset_key_for_depot(depot),
        line_strings: lines
      }
      File.write(DEPOT_CACHE_DIR.join("#{depot[:id]}.json"), JSON.pretty_generate(payload))
      true
    end

    def self.refresh_all_depot_caches!(depots: MetroDepotCatalog::DEPOTS)
      FileUtils.mkdir_p(DEPOT_CACHE_DIR)
      updated = []

      depots.each do |depot|
        if refresh_depot_cache!(depot)
          updated << depot[:id]
          puts "NLSC spur cache: #{depot[:id]} (#{depot[:name]})"
        end
      end

      updated
    end

    def self.ensure_dataset!(key)
      config = DATASETS.fetch(key)
      zip_path = CACHE_DIR.join(config[:zip])
      return zip_path if zip_path.exist?

      FileUtils.mkdir_p(CACHE_DIR)
      download!(config[:url], zip_path)
      zip_path
    end

    def self.line_strings_for_dataset(key)
      @line_cache ||= {}
      return @line_cache[key] if @line_cache.key?(key)

      zip_path = ensure_dataset!(key)
      @line_cache[key] = NlscShapefileReader.line_strings_from_zip(zip_path)
    rescue StandardError => error
      warn "NLSC railway dataset #{key} unavailable: #{error.message}"
      @line_cache[key] = []
    end

    def self.download!(url, destination)
      uri = URI(url)
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", read_timeout: 120) do |http|
        request = Net::HTTP::Get.new(uri)
        response = http.request(request)
        raise "HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

        File.binwrite(destination, response.body)
      end
    end

    private_class_method :download!
  end
end
