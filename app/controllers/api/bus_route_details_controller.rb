# frozen_string_literal: true

module Api
  class BusRouteDetailsController < ApplicationController
    def index
      render json: Transit::BusRouteDetailsQuery.new(route_id: params[:route_id]).call
    end
  end
end
