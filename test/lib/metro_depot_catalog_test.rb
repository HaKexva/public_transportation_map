# frozen_string_literal: true

require "test_helper"

class MetroDepotCatalogTest < ActiveSupport::TestCase
  test "exported depots keep catalog coordinates and expose track links when off the main line" do
    catalog_by_id = Geojson::MetroDepotCatalog::DEPOTS.index_by { |depot| depot[:id] }
    depots = Geojson::MetroDepotCatalog.to_json

    assert depots.length.positive?

    depots.each do |depot|
      catalog = catalog_by_id[depot[:id]]
      assert catalog, "missing catalog entry for #{depot[:id]}"

      assert_in_delta catalog[:lon].round(6), depot[:lon], 0.000001
      assert_in_delta catalog[:lat].round(6), depot[:lat], 0.000001

      nearest_distance = depot[:routes].filter_map do |route_id|
        path = Geojson::MetroDepotCatalog.send(:route_geojson_path, route_id)
        next unless path

        _track_lon, _track_lat, distance = Geojson::TrackGeometry.nearest_on_line_strings(
          depot[:lon],
          depot[:lat],
          Geojson::TrackGeometry.route_line_strings_from_geojson(path)
        )

        distance
      end.min

      link = (depot[:track_links] || []).min_by do |entry|
        entry[:coordinates]&.length || Float::INFINITY
      end

      if nearest_distance && nearest_distance > Geojson::TrackGeometry::DEPOT_EXTENSION_THRESHOLD_M
        assert link, "#{depot[:id]} should include a track link when >#{Geojson::TrackGeometry::DEPOT_EXTENSION_THRESHOLD_M}m from the route"
        assert link[:coordinates].length >= 2
        assert_in_delta depot[:lon], link[:coordinates].last[0], 0.000001
        assert_in_delta depot[:lat], link[:coordinates].last[1], 0.000001
      end
    end
  end
end
