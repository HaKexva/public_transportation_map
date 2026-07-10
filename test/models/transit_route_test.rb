# frozen_string_literal: true

require "test_helper"

class TransitRouteTest < ActiveSupport::TestCase
  test "manifest lookup resolves system and route id" do
    route = TransitRoute.create!(
      system_id: "taipei_metro",
      route_id: "bannan",
      name: "板南線",
      line_ref: "BL"
    )

    assert_equal route, TransitRoute.find_by_manifest!(system_id: "taipei_metro", route_id: "bannan")
  end
end
