# frozen_string_literal: true

module Api
  class BusRouteArrivalsController < ApplicationController
    def index
      render json: Transit::BusRouteArrivalsQuery.new(route_id: params[:route_id]).call
    end
  end
end
