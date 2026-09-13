# frozen_string_literal: true

require "test_helper"

class BusGeojsonRedirectsControllerTest < ActionDispatch::IntegrationTest
  test "redirects legacy flat bus path to nested city band file" do
    get "/geojson/bus/keelung_107.geojson"

    assert_response :moved_permanently
    assert_redirected_to "/geojson/bus/keelung_bus/100-199/keelung_107.geojson"
  end

  test "returns not found for unknown bus slug" do
    get "/geojson/bus/keelung_does_not_exist_zzz.geojson"

    assert_response :not_found
  end
end
