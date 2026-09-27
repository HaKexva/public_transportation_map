# frozen_string_literal: true

require "test_helper"

class DashboardsCartoKeyTest < ActionDispatch::IntegrationTest
  setup do
    @previous_key = ENV["CARTO_API_KEY"]
  end

  teardown do
    ENV["CARTO_API_KEY"] = @previous_key
  end

  test "passes CARTO API key to the map controller" do
    ENV["CARTO_API_KEY"] = " test-carto-key "

    get root_path

    assert_response :success
    assert_select "[data-controller~='map'][data-map-carto-api-key-value='test-carto-key']"
  end

  test "renders an empty CARTO key when unset" do
    ENV.delete("CARTO_API_KEY")

    get root_path

    assert_response :success
    assert_select "[data-controller~='map'][data-map-carto-api-key-value='']"
  end
end
