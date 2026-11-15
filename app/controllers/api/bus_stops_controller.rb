# frozen_string_literal: true

module Api
  class BusStopsController < ApplicationController
    def index
      result = Transit::LayerPlaceSearch.new(query: params[:q], city_id: params[:city_id]).call
      render json: { stops: result[:stops], places: result[:places] }
    end
  end
end
