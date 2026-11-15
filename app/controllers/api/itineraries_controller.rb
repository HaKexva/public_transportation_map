# frozen_string_literal: true

module Api
  class ItinerariesController < ApplicationController
    def create
      graph = Transit::Itinerary::Graph.current
      origin = Transit::Itinerary::PlaceResolver.call(place_param(:origin), graph:)
      destination = Transit::Itinerary::PlaceResolver.call(place_param(:destination), graph:)
      if origin.nil? || destination.nil?
        render json: { error: "place_not_found", itineraries: [] }, status: :unprocessable_entity
        return
      end

      depart_at = Time.zone.parse(params[:depart_at].to_s) || Time.current
      router = Transit::Itinerary::Router.new(graph, origin:, destination:, depart_at:)
      itineraries = router.call
      corridor = Transit::Itinerary::Corridor.call(itineraries)
      render json: { itineraries:, corridor:, notice: router.notice }
    end

    def places
      places = Transit::Itinerary::PlaceResolver.search(params[:q], graph: Transit::Itinerary::Graph.current)
      render json: { places: }
    end

    private

    def place_param(key)
      raw = params[key]
      return { query: raw.to_s } if raw.is_a?(String)
      return {} unless raw.respond_to?(:permit)

      raw.permit(:lat, :lon, :query, :name).to_h.symbolize_keys
    end
  end
end
