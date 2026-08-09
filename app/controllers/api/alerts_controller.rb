# frozen_string_literal: true

module Api
  class AlertsController < ApplicationController
    def index
      render json: { alerts: Transit::MetroAlertFeed.call }
    end
  end
end
