# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module Geojson
  # Fills blank 經度／緯度 of hand-added depots in BusDepotWriter::STATIONS_PATH by
  # geocoding the address written in their 備註 column (Google Geocoding API).
  class BusDepotGeocoder
    ENDPOINT = "https://maps.googleapis.com/maps/api/geocode/json"
    APPROXIMATE_NOTE = "・座標約略，請確認"

    Result = Data.define(:filled, :failed)

    def self.call(manual_path: BusDepotWriter::STATIONS_PATH, api_key: GoogleMaps.api_key, lookup: nil)
      new(manual_path:, api_key:, lookup:).call
    end

    def initialize(manual_path:, api_key:, lookup: nil)
      @manual_path = manual_path
      @api_key = api_key
      @lookup = lookup || method(:google_lookup)
    end

    def call
      manual = BusDepotWriter.parse_manual(@manual_path)
      filled = []
      failed = []

      manual.depots.each do |row|
        next if BusDepotWriter.auto_code?(row["code"]) || row["lon"].present? || row["lat"].present?

        address = self.class.address_from_note(row["note"])
        next if address.blank?

        hit = @lookup.call(address)
        if hit.nil?
          failed << row["code"]
          next
        end

        row["lon"] = hit[:lon].round(6).to_s
        row["lat"] = hit[:lat].round(6).to_s
        row["note"] = "#{row['note']}#{APPROXIMATE_NOTE}" if hit[:approximate] && !row["note"].include?(APPROXIMATE_NOTE)
        filled << row["code"]
      end

      intro = {
        BusDepotWriter::CONFIRMED_BASENAME => BusDepotWriter::CONFIRMED_INTRO,
        BusDepotWriter::STATIONS_BASENAME => BusDepotWriter::STATIONS_INTRO
      }.fetch(File.basename(@manual_path), BusDepotWriter::MANUAL_INTRO)
      File.write(@manual_path, BusDepotWriter.manual_markdown(depot_rows: manual.depots, route_rows: manual.routes, intro:))
      Result.new(filled:, failed:)
    end

    # Drops parenthetical remarks such as 「（與臺北客運共用場地）」.
    def self.address_from_note(note)
      note.to_s.gsub(/[（(][^）)]*[）)]/, "").split("・").first.to_s.strip
    end

    private

    def google_lookup(address)
      raise "GOOGLE_MAPS_API_KEY is not configured" if @api_key.blank?

      uri = URI(ENDPOINT)
      uri.query = URI.encode_www_form(address:, key: @api_key, language: "zh-TW", region: "tw", components: "country:TW")
      payload = JSON.parse(Net::HTTP.get(uri))
      case payload["status"]
      when "OK"
        result = payload["results"].first
        location = result.dig("geometry", "location")
        approximate = result["partial_match"] || result.dig("geometry", "location_type") == "APPROXIMATE"
        { lon: location["lng"].to_f, lat: location["lat"].to_f, approximate: approximate.present? }
      when "ZERO_RESULTS"
        nil
      else
        raise "Google Geocoding #{payload['status']}: #{payload['error_message']}"
      end
    end
  end
end
