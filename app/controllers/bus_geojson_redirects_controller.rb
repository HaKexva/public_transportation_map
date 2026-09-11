# frozen_string_literal: true

# Legacy flat bus URLs (/geojson/bus/:slug.geojson) redirect to nested city/band paths.
# Keeps stale cached routes.json working after bus_reorganize.
class BusGeojsonRedirectsController < ApplicationController
  def show
    basename = params[:slug].to_s
    return head :not_found if basename.blank? || basename.include?("/") || basename.include?("\\")

    slug = basename.delete_suffix(".geojson")
    return head :not_found if slug.blank? || slug == basename

    path = Geojson::BusLayout.find_geojson(slug)
    return head :not_found unless path&.exist?

    redirect_to Geojson::BusLayout.public_url(path), status: :moved_permanently, allow_other_host: false
  end
end
