# frozen_string_literal: true

module Api
  class BusArrivalsController < ApplicationController
    def index
      payload = Transit::BusArrivalQuery.new(
        city_id: params[:city_id],
        stop_uid: params[:stop_uid].presence || params[:ref],
        route_name: params[:route_name]
      ).call

      render json: payload
    end
  end
end
