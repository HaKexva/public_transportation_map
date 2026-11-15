# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module Transit
  module Itinerary
    # Server-side address lookup. The Maps JavaScript key stays out of this call's response.
    class Geocoder
      ENDPOINT = "https://maps.googleapis.com/maps/api/geocode/json"
      DEFAULT_LIMIT = 5
      CITY_SUFFIX = /[市縣]\z/
      DISTRICT_SUFFIX = /[鄉鎮市區]\z/
      VILLAGE_SUFFIX = /[里村]\z/

      def self.lookup(query, api_key: GoogleMaps.api_key)
        search(query, limit: 1, api_key:).first&.slice("lat", "lon", "name")
      end

      def self.search(query, limit: DEFAULT_LIMIT, api_key: GoogleMaps.api_key)
        return [] if query.blank? || api_key.blank?

        uri = URI(ENDPOINT)
        uri.query = URI.encode_www_form(
          address: query,
          key: api_key,
          language: "zh-TW",
          region: "tw",
          components: "country:TW"
        )
        payload = JSON.parse(Net::HTTP.get(uri))
        return [] unless payload["status"] == "OK"

        Array(payload["results"]).first(limit).filter_map { |result| serialize(result, query) }
      rescue StandardError
        []
      end

      def self.serialize(result, query)
        location = result&.dig("geometry", "location")
        return unless location

        admin = admin_label(result["address_components"])
        name = display_name(result, query, admin)
        {
          "lat" => location["lat"].to_f,
          "lon" => location["lng"].to_f,
          "name" => name,
          "admin" => admin,
          "kind" => "place",
          "place_id" => result["place_id"].presence,
          "types" => Array(result["types"])
        }.compact
      end

      def self.admin_label(components)
        rows = Array(components)
        city = component_named(rows, "administrative_area_level_1") ||
          first_matching(rows, CITY_SUFFIX)
        district = district_name(rows, city)
        village = village_name(rows, city, district)
        [ city, district, village ].compact_blank.join
      end

      def self.district_name(rows, city)
        candidates = [
          component_named(rows, "administrative_area_level_2"),
          component_named(rows, "administrative_area_level_3"),
          component_named(rows, "locality"),
          component_named(rows, "sublocality"),
          component_named(rows, "sublocality_level_1")
        ].compact_blank.uniq
        candidates.find { |name| name != city && name.match?(DISTRICT_SUFFIX) && !name.match?(VILLAGE_SUFFIX) }
      end

      def self.village_name(rows, city, district)
        candidates = rows.filter_map { |row| row["long_name"].to_s.presence }
        candidates.find do |name|
          name != city && name != district && name.match?(VILLAGE_SUFFIX)
        end
      end

      def self.component_named(rows, type)
        rows.find { |row| Array(row["types"]).include?(type) }&.dig("long_name").presence
      end

      def self.first_matching(rows, pattern)
        rows.filter_map { |row| row["long_name"].to_s.presence }.find { |name| name.match?(pattern) }
      end

      def self.display_name(result, query, admin)
        raw = result["formatted_address"].to_s
        name = raw
          .sub(/\A\d{3,5}\s*/, "")
          .sub(/\A台灣/, "")
          .sub(/\ATaiwan,?\s*/i, "")
          .strip
        name = name.split(",", 2).first.to_s.strip
        if admin.present? && name.start_with?(admin)
          remainder = name.delete_prefix(admin).sub(/\A[,\s]+/, "").strip
          return remainder if remainder.present?
        end
        return query.to_s if name.blank? || name == admin

        name
      end
      private_class_method :serialize, :admin_label, :district_name, :village_name,
        :component_named, :first_matching, :display_name
    end
  end
end
