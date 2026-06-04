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

  test "xindian depot connects via xiaobitan branch not songshan xindian main line" do
    depot = Geojson::MetroDepotCatalog::DEPOTS.find { |entry| entry[:id] == "xindian_depot" }

    assert_equal "xiaobitan_branch", Geojson::MetroDepotCatalog.depot_track_route_id(depot)

    serialized = Geojson::MetroDepotCatalog.to_json.find { |entry| entry[:id] == "xindian_depot" }
    assert_equal "xiaobitan_branch", serialized[:track_links].sole[:route_id]

    songshan = JSON.parse(Rails.root.join("public/geojson/taipei_metro/songshan_xindian.geojson").read)
    assert_not songshan.fetch("features").any? { |feature| feature.dig("properties", "depot_id") == "xindian_depot" }

    xiaobitan = JSON.parse(Rails.root.join("public/geojson/taipei_metro/xiaobitan_branch.geojson").read)
    spur = xiaobitan.fetch("features").find { |feature| feature.dig("properties", "depot_id") == "xindian_depot" }

    assert spur, "expected 新店機廠支線 on 小碧潭支線 GeoJSON"
    assert_equal "新店機廠支線", spur.dig("properties", "name")
  end

  test "includes hsr and other maintenance facilities" do
    depots = Geojson::MetroDepotCatalog.to_json
    ids = depots.map { |entry| entry[:id] }

    assert_includes ids, "hsr_yanchao_depot"
    assert_includes ids, "maokong_depot"
    assert_includes ids, "sun_moon_ropeway_depot"
    assert_includes ids, "skytrain_depot"

    hsr = depots.find { |entry| entry[:id] == "hsr_wuri_depot" }
    assert_equal %w[taiwan_hsr], hsr[:routes]
    assert hsr[:track_links].any? { |link| link[:route_id] == "taiwan_hsr" }

    maokong = JSON.parse(Rails.root.join("public/geojson/other/maokong_gondola.geojson").read)
    assert maokong.fetch("features").any? { |f| f.dig("properties", "depot_id") == "maokong_depot" }
  end
end
