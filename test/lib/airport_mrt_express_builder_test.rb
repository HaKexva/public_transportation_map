# frozen_string_literal: true

require "test_helper"

class AirportMrtExpressBuilderTest < ActiveSupport::TestCase
  test "builds express geojson with ordered stops along the main line" do
    Geojson::AirportMrtExpressBuilder.build!

    path = Rails.root.join("public/geojson/taoyuan_metro/airport_mrt_express.geojson")
    data = JSON.parse(path.read)

    route = data.fetch("features").find { |feature| feature.dig("properties", "feature_type") == "express_route" }
    assert route, "expected express route feature"

    stops = data.fetch("features").select { |feature| feature.dig("properties", "express_service") }
    assert_equal Geojson::AirportMrtExpressBuilder::EXPRESS_STOP_REFS, stops.map { |stop| stop.dig("properties", "ref") }
    assert_operator route.dig("geometry", "coordinates").length, :>, 100
  end
end
