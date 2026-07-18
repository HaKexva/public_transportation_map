# frozen_string_literal: true

require "net/http"
require "rexml/document"
require "uri"

module Geojson
  # Fetches OSM elements via the 0.6 API when Overpass is unavailable.
  class OsmApiClient
    API_BASE = "https://api.openstreetmap.org/api/0.6"

    def self.way_elements(way_id)
      doc = get("way/#{way_id}/full")
      nodes = index_nodes(doc)
      elements = []

      doc.elements.each("osm/way") do |way|
        next unless way.attributes["id"].to_i == way_id.to_i

        geometry = way_geometry(way, nodes)
        next if geometry.length < 2

        elements << { "type" => "way", "id" => way_id.to_i, "geometry" => geometry }
      end

      elements
    end

    def self.relation_way_elements(relation_id)
      doc = get("relation/#{relation_id}/full")
      way_ids = []

      doc.elements.each("osm/relation/member") do |member|
        next unless member.attributes["type"] == "way"

        way_ids << member.attributes["ref"].to_i
      end

      way_ids.flat_map { |way_id| way_elements(way_id) }
    end

    def self.relation_node_elements(relation_id)
      doc = get("relation/#{relation_id}/full")
      nodes = index_node_elements(doc)
      station_nodes = []

      doc.elements.each("osm/relation/member") do |member|
        next unless member.attributes["type"] == "node"

        node = nodes[member.attributes["ref"].to_i]
        station_nodes << node if node
      end

      station_nodes
    end

    def self.way_node_elements(way_id)
      doc = get("way/#{way_id}/full")
      index_node_elements(doc)
    end

    def self.get(path)
      uri = URI("#{API_BASE}/#{path}")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 30
      http.read_timeout = 90

      response = http.get(uri.request_uri)
      raise "OSM API request failed (#{response.code}) for #{path}" unless response.is_a?(Net::HTTPSuccess)

      REXML::Document.new(response.body)
    end

    def self.index_nodes(doc)
      nodes = {}

      doc.elements.each("osm/node") do |node|
        nodes[node.attributes["id"].to_i] = {
          "lat" => node.attributes["lat"].to_f,
          "lon" => node.attributes["lon"].to_f
        }
      end

      nodes
    end

    def self.index_node_elements(doc)
      nodes = {}

      doc.elements.each("osm/node") do |node|
        tags = {}
        node.elements.each("tag") { |tag| tags[tag.attributes["k"]] = tag.attributes["v"] }

        nodes[node.attributes["id"].to_i] = {
          "type" => "node",
          "id" => node.attributes["id"].to_i,
          "lat" => node.attributes["lat"].to_f,
          "lon" => node.attributes["lon"].to_f,
          "tags" => tags
        }
      end

      nodes
    end

    def self.way_geometry(way, nodes)
      way.elements.to_a("nd").filter_map do |nd|
        nodes[nd.attributes["ref"].to_i]
      end
    end

    private_class_method :index_nodes, :index_node_elements, :way_geometry
  end
end
