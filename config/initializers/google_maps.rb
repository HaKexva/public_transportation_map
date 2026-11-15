# frozen_string_literal: true

# Taiwan main island, Penghu, Kinmen, and Matsu.
# The Leaflet basemap loads this key in the browser through the Maps JavaScript API.
# Billing must be enabled on the Cloud project — otherwise tiles/Street View show
# “For development purposes only”. Enable "Maps JavaScript API" (Street View
# panorama uses it; optionally also Street View Static API) and restrict the key
# by HTTP referrer. Sidebar landmark search also calls Geocoding API server-side
# with the same key — enable Geocoding API (IP restriction is fine).
module GoogleMaps
  CENTER = { lat: 24.15, lng: 120.2 }.freeze
  ZOOM = 6
  LANGUAGE = "zh-TW"
  REGION = "TW"

  def self.api_key
    return ENV["GOOGLE_MAPS_API_KEY"] if ENV["GOOGLE_MAPS_API_KEY"].present?

    Rails.application.credentials.dig(:google_maps, :api_key)
  rescue ActiveSupport::MessageEncryptor::InvalidMessage
    nil
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
