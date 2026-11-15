# frozen_string_literal: true

class DashboardsController < ApplicationController
  def show
    page_mode = params[:page_mode].presence_in(%w[lookup plan]) || "lookup"
    transport_mode = params[:transport_mode].presence_in(%w[rail bus]) || "rail"
    transport_mode = "rail" if page_mode == "plan"

    render Views::Dashboards::Show.new(
      routes_manifest: RouteCatalog.manifest,
      page_mode: page_mode,
      transport_mode: transport_mode
    )
  end
end
