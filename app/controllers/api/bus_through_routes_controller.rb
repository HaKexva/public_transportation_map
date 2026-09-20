# frozen_string_literal: true

module Api
  class BusThroughRoutesController < ApplicationController
    def index
      payload = Transit::BusThroughRoutesQuery.new(
        city_id: params[:city_id],
        station_id: params[:station_id],
        name: params[:name],
        lat: params[:lat],
        lon: params[:lon]
      ).call

      render json: { routes: payload.routes, error: payload.error }.compact
    end
  end
end
