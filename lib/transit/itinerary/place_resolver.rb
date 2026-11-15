# frozen_string_literal: true

module Transit
  module Itinerary
    class PlaceResolver
      # Modes that share short city names (台中 / 臺中, 桃園, 新竹…) need the
      # system in the visible label — 台 vs 臺 is too easy to miss.
      LABELED_KINDS = %w[rail hsr metro ferry flight].freeze

      class << self
        attr_accessor :geocoder

        def call(input, graph: Graph.current)
          raw = input.respond_to?(:to_h) ? input.to_h.symbolize_keys : {}
          lat = raw[:lat]
          lon = raw[:lon]
          if lat.present? && lon.present?
            name = raw[:name].presence || raw[:query].presence || I18n.t("map.itinerary.map_point")
            return { "name" => name, "lat" => lat.to_f, "lon" => lon.to_f }
          end

          query = raw[:query].to_s.strip
          return nil if query.blank?

          found = search(query, graph:, limit: 1).first
          return resolved(found) if found

          geocode(query)
        end

        # Itinerary legs read `name`; prefer the mode-tagged label so 台中／臺中
        # stay distinguishable after the rider confirms a suggestion.
        def resolved(place)
          return place if place.blank?

          place.merge("name" => place["label"].presence || place["name"])
        end

        def search(query, graph: Graph.current, limit: 8)
          places = []
          seen = {}
          append = lambda do |place|
            return if places.length >= limit

            key = [ place["lat"].to_f.round(4), place["lon"].to_f.round(4), Geometry.normalize(place["name"]), place["kind"].to_s ]
            return if seen[key]

            seen[key] = true
            places << decorate(place)
          end

          # Pull extra graph hits so a shared name like 西門 still keeps metro
          # ahead of out-of-town bus poles after dedupe.
          graph.search_stops(query, limit: [ limit * 3, 12 ].max).each do |place|
            append.call(place.merge("kind" => place["kind"]))
          end
          if places.length < limit
            BusStopSearch.new(query:).call.each do |stop|
              append.call(
                "name" => stop["name"],
                "name_en" => stop["name_en"],
                "lat" => stop["lat"],
                "lon" => stop["lon"],
                "kind" => "bus",
                "detail" => [ stop["city"], stop["place"] ].compact.join(" · ")
              )
            end
          end
          places.first(limit)
        end

        def decorate(place)
          kind = place["kind"].to_s
          kind_label = kind_label_for(kind)
          if kind_label && LABELED_KINDS.include?(kind)
            place["label"] = "#{place["name"]}（#{kind_label}）"
            place["detail"] = [ kind_label, place["detail"] ].compact_blank.join(" · ")
          elsif kind_label && place["detail"].blank?
            place["detail"] = kind_label
          end
          place
        end

        def kind_label_for(kind)
          return if kind.blank?

          I18n.t("map.itinerary.kinds.#{kind}", default: nil)
        end

        def geocode(query)
          lookup = geocoder || Geocoder.method(:lookup)
          found = lookup.call(query)
          return nil if found.nil?

          decorate(
            "name" => found["name"].presence || query,
            "lat" => found["lat"].to_f,
            "lon" => found["lon"].to_f,
            "kind" => "address"
          )
        rescue StandardError
          nil
        end
      end
    end
  end
end
