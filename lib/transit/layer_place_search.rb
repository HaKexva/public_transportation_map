# frozen_string_literal: true

module Transit
  # Sidebar layer search: bus poles plus optional Google landmarks.
  class LayerPlaceSearch
    PLACE_LIMIT = 5
    DUPLICATE_METERS = 40.0
    EARTH_RADIUS_M = 6_371_000.0

    def initialize(query:, city_id: nil, bus_root: nil, geocoder: nil, configured: nil)
      @query = query.to_s
      @city_id = city_id
      @bus_root = bus_root
      @geocoder = geocoder || Transit::Itinerary::Geocoder.method(:search)
      @configured = configured.nil? ? GoogleMaps.configured? : configured
    end

    def call
      stops = BusStopSearch.new(query: @query, city_id: @city_id, bus_root: @bus_root).call
      { stops: stops, places: places_for(stops) }
    end

    private

    def places_for(stops)
      return [] unless @configured
      return [] unless BusStopSearch.ready?(BusStopSearch.normalize(@query))

      @geocoder.call(@query, limit: PLACE_LIMIT).filter_map { |hit| serialize_place(hit, stops) }
    rescue StandardError
      []
    end

    def serialize_place(hit, stops)
      lat = hit["lat"].to_f
      lon = hit["lon"].to_f
      name = hit["name"].to_s.presence || @query
      return if near_duplicate_stop?(stops, name, lat, lon)

      {
        "name" => name,
        "label" => name,
        "lat" => lat,
        "lon" => lon,
        "city" => hit["admin"].presence,
        "kind" => "place",
        "place_id" => hit["place_id"].presence
      }.compact
    end

    def near_duplicate_stop?(stops, name, lat, lon)
      needle = BusStopSearch.normalize(name)
      stops.any? do |stop|
        next false unless meters_between(lat, lon, stop["lat"].to_f, stop["lon"].to_f) <= DUPLICATE_METERS

        stop_name = BusStopSearch.normalize(stop["name"])
        label = BusStopSearch.normalize(stop["label"])
        stop_name.include?(needle) || needle.include?(stop_name) ||
          (label.present? && (label.include?(needle) || needle.include?(label)))
      end
    end

    def meters_between(lat1, lon1, lat2, lon2)
      d_lat = (lat2 - lat1) * Math::PI / 180.0
      d_lon = (lon2 - lon1) * Math::PI / 180.0
      a = Math.sin(d_lat / 2)**2 +
        Math.cos(lat1 * Math::PI / 180.0) * Math.cos(lat2 * Math::PI / 180.0) *
          Math.sin(d_lon / 2)**2
      2 * EARTH_RADIUS_M * Math.asin(Math.sqrt(a))
    end
  end
end
