# frozen_string_literal: true

require "test_helper"

class MetroDepotCatalogTest < ActiveSupport::TestCase
  test "exported depots sit on linked route tracks" do
    depots = Geojson::MetroDepotCatalog.to_json

    assert depots.length.positive?

    depots.each do |depot|
      nearest_distance = depot[:routes].filter_map do |route_id|
        path = Geojson::MetroDepotCatalog.send(:route_geojson_path, route_id)
        next unless path

        _lon, _lat, distance = Geojson::MetroDepotCatalog.send(
          :nearest_on_route_tracks,
          depot[:lon],
          depot[:lat],
          path
        )

        distance
      end.min

      assert nearest_distance && nearest_distance < 50,
             "#{depot[:id]} should be within 50m of a linked route track (was #{nearest_distance&.round(1)}m)"
    end
  end
end
