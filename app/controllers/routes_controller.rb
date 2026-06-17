# frozen_string_literal: true

class RoutesController < ApplicationController
  def show
    route = RouteCatalog.find!(params[:id])
    system_label = RouteCatalog.system_label(route["system_id"])

    render Views::Routes::Show.new(route: route, system_label: system_label)
  end
end
