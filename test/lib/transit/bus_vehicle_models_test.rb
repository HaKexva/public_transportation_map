# frozen_string_literal: true

require "test_helper"

class TransitBusVehicleModelsTest < ActiveSupport::TestCase
  setup do
    Transit::BusVehicleModels.entries = [
      { "model" => "A", "operator_id" => "100", "plates" => [ "EAL-" ] },
      { "model" => "B", "plates" => [ "EAL-01" ] },
      { "model" => "C", "plates" => [ "-U3" ] }
    ]
  end

  teardown do
    Transit::BusVehicleModels.entries = nil
  end

  test "matches plate series, preferring the longest pattern" do
    assert_equal "A", Transit::BusVehicleModels.lookup("EAL-0201", "100")
    assert_equal "B", Transit::BusVehicleModels.lookup("eal-0123", "100")
    assert_equal "C", Transit::BusVehicleModels.lookup("845-U3", "999")
    assert_nil Transit::BusVehicleModels.lookup("EAL-0201", "200")
  end

  test "derives the registration series from a plate" do
    assert_equal "EAL-", Transit::BusVehicleModels.series("EAL-0201")
    assert_equal "-U3", Transit::BusVehicleModels.series("845-U3")
    assert_nil Transit::BusVehicleModels.series("TEST011")
  end

  test "ships a valid config file" do
    assert_kind_of Array, Transit::BusVehicleModels.load_entries
  end
end
