# frozen_string_literal: true

# Taiwan main island, Penghu, Kinmen, and Matsu.
# Enable "Maps JavaScript API" (not only Maps Embed API) in Google Cloud Console.
module GoogleMaps
  CENTER = { lat: 24.15, lng: 120.2 }.freeze
  ZOOM = 6
  LANGUAGE = "zh-TW"
  REGION = "TW"

  def self.api_key
    ENV["GOOGLE_MAPS_API_KEY"].presence ||
      Rails.application.credentials.dig(:google_maps, :api_key)
  end

  def self.configured?
    api_key.present?
  end

  def self.embed_url
    return unless configured?

    params = {
      key: api_key,
      center: "#{CENTER[:lat]},#{CENTER[:lng]}",
      zoom: ZOOM,
      maptype: "roadmap",
      language: LANGUAGE,
      region: REGION
    }

    "https://www.google.com/maps/embed/v1/view?#{params.to_query}"
  end
end
