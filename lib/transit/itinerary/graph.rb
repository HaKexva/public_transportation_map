# frozen_string_literal: true

require "json"

module Transit
  module Itinerary
    # Compact stop / route / transfer graph. Built by Compiler and cached in memory.
    class Graph
      DEFAULT_NAME = "itinerary_graph.json"

      attr_reader :stops, :routes, :patterns, :serving, :foot

      def self.path
        @path || Rails.root.join("storage", DEFAULT_NAME)
      end

      def self.path=(value)
        @path = value
        @cached = nil
        @cached_stamp = nil
      end

      def self.current
        return @override if @override

        file = path
        return empty unless file.exist?

        stamp = file.mtime.to_f
        if @cached.nil? || @cached_stamp != stamp
          @cached = load_file(file)
          @cached_stamp = stamp
        end
        @cached
      end

      def self.override=(graph)
        @override = graph
      end

      def self.clear_override!
        @override = nil
      end

      def self.empty
        new("stops" => [], "routes" => [], "transfers" => [])
      end

      def self.load_file(path)
        new(JSON.parse(File.read(path)))
      rescue JSON::ParserError
        empty
      end

      def initialize(data)
        @stops = Array(data["stops"])
        @routes = Array(data["routes"])
        @transfers = Array(data["transfers"])
        index!
      end

      def write(path = self.class.path)
        FileUtils.mkdir_p(File.dirname(path))
        payload = {
          "stops" => @stops,
          "routes" => @routes,
          "transfers" => @transfers
        }
        File.write(path, JSON.generate(payload))
        self.class.instance_variable_set(:@cached, nil)
        self
      end

      # Prefer rail/metro when many bus poles share a short station name (西門).
      KIND_RANK = {
        "metro" => 0,
        "rail" => 1,
        "hsr" => 1,
        "ferry" => 2,
        "flight" => 3,
        "bus" => 4
      }.freeze

      def search_stops(query, limit: 8)
        needle = Geometry.normalize(query)
        return [] if needle.length < 2

        matches = []
        @norm_names.each_with_index do |name, id|
          name_en = @norm_ens[id]
          next unless name.include?(needle) || (name_en.present? && name_en.include?(needle))

          rank = name == needle || name_en == needle ? 0 : 1
          kind_rank = KIND_RANK.fetch(@stops[id]["kind"].to_s, 9)
          matches << [ rank, name.length, kind_rank, id ]
        end
        # Prefer rail/metro/ferry over a shorter flight label (綠島 vs 綠島機場).
        matches.sort_by { |rank, length, kind_rank, id| [ rank, kind_rank, length, id ] }
          .first(limit)
          .map { |_rank, _length, _kind, id| place_for(id) }
      end

      def place_for(id)
        stop = @stops[id]
        {
          "name" => stop["name"],
          "name_en" => stop["name_en"],
          "lat" => stop["lat"],
          "lon" => stop["lon"],
          "kind" => stop["kind"]
        }
      end

      def stops_near(lat, lon, meters, limit: 16)
        return [] if @stops.empty?

        lat_i, lon_i = Geometry.cell_index(lat, lon)
        radius = (meters / Geometry::CELL_METERS).ceil + 1
        found = []
        (lat_i - radius..lat_i + radius).each do |row|
          (lon_i - radius..lon_i + radius).each do |col|
            Array(@grid["#{row}:#{col}"]).each do |id|
              stop = @stops[id]
              distance = Geometry.meters(lat, lon, stop["lat"], stop["lon"])
              found << [ id, distance ] if distance <= meters
            end
          end
        end
        found.sort_by(&:last).first(limit)
      end

      def route_at(pattern)
        @routes[pattern["route_index"]]
      end

      private

      def index!
        @patterns = []
        @serving = Array.new(@stops.length) { [] }
        @routes.each_with_index do |route, route_index|
          Array(route["patterns"]).each do |pattern|
            stops = Array(pattern["stops"])
            next if stops.length < 2

            services = normalize_services(pattern["services"], stops.length)
            next if services.empty?

            index = @patterns.length
            @patterns << {
              "route_index" => route_index,
              "stops" => stops,
              "services" => services
            }
            stops.each_with_index do |stop_id, offset|
              @serving[stop_id] << [ index, offset ] if @serving[stop_id]
            end
          end
        end

        @foot = Array.new(@stops.length) { [] }
        @transfers.each do |from, to, minutes|
          next unless @foot[from] && @foot[to]

          @foot[from] << [ to, minutes.to_i ]
        end
        @norm_names = @stops.map { |stop| Geometry.normalize(stop["name"]) }
        @norm_ens = @stops.map { |stop| Geometry.normalize(stop["name_en"]) }
        build_grid
      end

      def normalize_services(services, stop_count)
        Array(services).each_with_object({}) do |(code, body), out|
          next unless body.is_a?(Hash)

          trips = Array(body["trips"]).filter_map { |trip| coerce_trip(trip, stop_count) }
          trips = trips.uniq.sort_by { |trip| trip["times"].first }
          headways = Array(body["headways"]).filter_map do |band|
            next unless band.is_a?(Hash)

            ride = Array(band["ride"]).map(&:to_i)
            next if ride.length != stop_count - 1
            next if band["every"].to_i <= 0

            {
              "start" => band["start"].to_i,
              "end" => band["end"].to_i,
              "every" => band["every"].to_i,
              "ride" => ride
            }
          end
          next if trips.empty? && headways.empty?

          out[code.to_s] = { "trips" => trips, "headways" => headways }
        end
      end

      def coerce_trip(trip, stop_count)
        if trip.is_a?(Hash) && (trip.key?("times") || trip.key?(:times))
          train = (trip["train"] || trip[:train]).to_s.presence
          raw = trip["times"] || trip[:times]
        else
          train = nil
          raw = trip
        end
        times = Array(raw).map { |value| value.nil? ? nil : value.to_i }
        return nil if times.length != stop_count || times.any?(&:nil?)

        { "train" => train, "times" => times }
      end

      def build_grid
        @grid = Hash.new { |hash, key| hash[key] = [] }
        @stops.each_with_index do |stop, id|
          lat_i, lon_i = Geometry.cell_index(stop["lat"], stop["lon"])
          @grid["#{lat_i}:#{lon_i}"] << id
        end
      end
    end
  end
end
