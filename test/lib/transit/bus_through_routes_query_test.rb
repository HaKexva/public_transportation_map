# frozen_string_literal: true

require "test_helper"

class Transit::BusThroughRoutesQueryTest < ActiveSupport::TestCase
  setup do
    @root = Rails.root.join("tmp/bus_through_routes_#{name}")
    FileUtils.rm_rf(@root)
    FileUtils.mkdir_p(@root.join("keelung_bus"))
    index = {
      "stations" => {
        "KLS" => [ { "id" => "keelung_101", "ref" => "101", "name" => "101", "color" => "#123" } ]
      },
      "clusters" => {
        "25.1280|121.7400|海洋廣場" => [
          { "id" => "keelung_103", "ref" => "103", "name" => "103", "color" => "#456" }
        ]
      }
    }
    File.write(@root.join("keelung_bus/_stop_routes.json"), JSON.pretty_generate(index))
  end

  teardown do
    FileUtils.rm_rf(@root)
  end

  test "matches by station id" do
    result = Transit::BusThroughRoutesQuery.new(city_id: "Keelung", station_id: "KLS", bus_root: @root).call
    assert_nil result.error
    assert_equal [ "keelung_101" ], result.routes.map { |row| row["id"] }
  end

  test "matches nearby cluster by name" do
    result = Transit::BusThroughRoutesQuery.new(
      city_id: "Keelung",
      name: "海洋廣場",
      lat: 25.1281,
      lon: 121.7401,
      bus_root: @root
    ).call
    assert_equal [ "keelung_103" ], result.routes.map { |row| row["id"] }
  end
end
