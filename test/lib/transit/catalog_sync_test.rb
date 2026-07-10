# frozen_string_literal: true

require "test_helper"

class TransitCatalogSyncTest < ActiveSupport::TestCase
  test "syncs routes and stations from manifest and geojson" do
    result = Transit::CatalogSync.sync!

    assert_operator result.routes, :>=, 30
    assert_operator result.stations, :>, 100

    bannan = TransitRoute.find_by_manifest!(system_id: "taipei_metro", route_id: "bannan")
    assert_equal "板南線", bannan.name
    assert_equal "BL", bannan.line_ref
    assert_operator bannan.transit_route_stations.count, :>=, 20

    tra = TransitRoute.find_by_manifest!(system_id: "tra", route_id: "western_trunk_north")
    assert tra.transit_route_stations.exists?(station_ref: "1010")
  end

  test "sync is idempotent" do
    first = Transit::CatalogSync.sync!
    second = Transit::CatalogSync.sync!

    assert_equal first.routes, second.routes
    assert_equal first.stations, second.stations
    assert_equal first.routes, TransitRoute.count
  end
end
