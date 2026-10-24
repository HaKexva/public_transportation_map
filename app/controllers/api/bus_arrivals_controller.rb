# frozen_string_literal: true

module Api
  class BusArrivalsController < ApplicationController
    def index
      payload = Transit::BusArrivalQuery.new(
        city_id: params[:city_id],
        stop_uid: params[:stop_uid].presence || params[:ref],
        route_name: params[:route_name],
        stop_name: params[:stop_name],
        route_names: params[:route_names].to_s.split(","),
        city_ids: params[:city_ids].to_s.split(","),
        stop_uids: params[:stop_uids].to_s.split(",")
      ).call

      render json: payload
    end
  end
end
