# frozen_string_literal: true

class DashboardsController < ApplicationController
  def show
    render Views::Dashboards::Show.new(routes_manifest: RouteCatalog.manifest)
  end
end
