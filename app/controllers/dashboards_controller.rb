# frozen_string_literal: true

class DashboardsController < ApplicationController
  def show
    transport_mode = params[:transport_mode].presence_in(%w[rail bus]) || "rail"
    render Views::Dashboards::Show.new(
      routes_manifest: RouteCatalog.manifest,
      transport_mode: transport_mode
    )
  end
end
