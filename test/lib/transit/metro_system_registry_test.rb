# frozen_string_literal: true

require "test_helper"

class TransitMetroSystemRegistryTest < ActiveSupport::TestCase
  test "maps the Taichung green line by its TDX line id" do
    assert_equal "green_line", Transit::MetroSystemRegistry.route_id_for(tdx_rail_system: "TMRT", line_id: "G")
    assert_equal "green_line", Transit::MetroSystemRegistry.route_id_for(tdx_rail_system: "TMRT", line_id: "1")
  end
end
