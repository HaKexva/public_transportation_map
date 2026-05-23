# frozen_string_literal: true

class DashboardsController < ApplicationController
  def show
    manifest_path = Rails.public_path.join("geojson/routes.json")
    routes_manifest = JSON.parse(manifest_path.read)

    render Views::Dashboards::Show.new(routes_manifest: routes_manifest)
  end
end
