# frozen_string_literal: true

module Api
  class StationInfosController < ApplicationController
    def index
      payload = Transit::StationInfoQuery.new(
        station_ref: params[:ref],
        route_id: params[:route_id].presence || params[:route]
      ).call

      render json: payload
    end
  end
end
