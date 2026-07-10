# frozen_string_literal: true

require "test_helper"

class MetroDepotCatalogTest < ActiveSupport::TestCase
  test "exported depots use OSM facility coordinates and expose track links when off the main line" do
    catalog_by_id = Geojson::MetroDepotCatalog::DEPOTS.index_by { |depot| depot[:id] }
    depots = Geojson::MetroDepotCatalog.to_json

    assert depots.length.positive?

    depots.each do |depot|
      catalog = catalog_by_id[depot[:id]]
      assert catalog, "missing catalog entry for #{depot[:id]}"

      facility = Geojson::MetroDepotCatalog.primary_facility_coordinates(catalog)
      assert_in_delta facility[:lon], depot[:lon], 0.000001
      assert_in_delta facility[:lat], depot[:lat], 0.000001

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
        next unless link

        assert link[:coordinates].length >= 2
        assert link[:coordinates].length > 2 || nearest_distance <= Geojson::TrackGeometry::DEPOT_EXTENSION_THRESHOLD_M * 2,
               "#{depot[:id]} should follow track geometry, not a straight shortcut"
        refute Geojson::TrackGeometry.straight_line?(link[:coordinates]) if link[:coordinates].length > 2
        assert link[:coordinates].length >= 3,
               "#{depot[:id]} should follow yard track geometry, not a straight shortcut" if link[:coordinates].length > 2
        end_gap = Geojson::TrackGeometry.planar_distance_meters(
          link[:coordinates].last[0],
          link[:coordinates].last[1],
          depot[:lon],
          depot[:lat]
        )
        assert_operator end_gap, :<=, 1_200,
                        "#{depot[:id]} spur should end near the facility (#{end_gap.round}m)"
        max_seg = link[:coordinates].each_cons(2).map do |start, finish|
          Geojson::TrackGeometry.planar_distance_meters(start[0], start[1], finish[0], finish[1])
        end.max
        assert_operator max_seg, :<, 700,
                        "#{depot[:id]} should not have a long closing chord (#{max_seg.round}m)"
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

  test "includes tra maintenance depots with track links" do
    depots = Geojson::MetroDepotCatalog.to_json
    ids = depots.map { |entry| entry[:id] }

    %w[
      tra_shulin_depot
      tra_qidu_depot
      tra_fugang_depot
      tra_changhua_depot
      tra_chaozhou_depot
      tra_hualien_depot
      tra_taitung_depot
      tra_yilan_depot
    ].each do |id|
      assert_includes ids, id
    end

    shulin = depots.find { |entry| entry[:id] == "tra_shulin_depot" }
    assert_equal %w[western_trunk_north], shulin[:routes]
    assert shulin[:track_links].any? { |link| link[:route_id] == "western_trunk_north" }

    north = JSON.parse(Rails.root.join("public/geojson/tra/western_trunk_north.geojson").read)
    assert north.fetch("features").any? { |feature| feature.dig("properties", "depot_id") == "tra_shulin_depot" }
  end

  test "includes taichung green line maintenance depot" do
    depots = Geojson::MetroDepotCatalog.to_json
    ids = depots.map { |entry| entry[:id] }

    assert_includes ids, "taichung_beitun_depot"

    beitun = depots.find { |entry| entry[:id] == "taichung_beitun_depot" }
    assert_equal "北屯機廠", beitun[:name]
    assert_equal %w[green_line], beitun[:routes]
    assert_equal "五級", beitun[:grade]
    assert beitun[:track_links].any? { |link| link[:route_id] == "green_line" }

    green = JSON.parse(Rails.root.join("public/geojson/taichung_metro/green_line.geojson").read)
    assert green.fetch("features").any? { |feature| feature.dig("properties", "depot_id") == "taichung_beitun_depot" }
  end

  test "includes hsr maintenance facilities without corridor-only yards" do
    depots = Geojson::MetroDepotCatalog.to_json
    ids = depots.map { |entry| entry[:id] }

    assert_includes ids, "hsr_yanchao_depot"
    refute_includes ids, "sun_moon_ropeway_depot"
    refute_includes ids, "skytrain_depot"

    hsr = depots.find { |entry| entry[:id] == "hsr_wuri_depot" }
    assert_equal %w[taiwan_hsr], hsr[:routes]
    assert hsr[:track_links].any? { |link| link[:route_id] == "taiwan_hsr" }

    yanchao = depots.find { |entry| entry[:id] == "hsr_yanchao_depot" }
    assert_operator yanchao[:lat], :>, 22.7635
    assert_operator yanchao[:lat], :<, 22.77

    north_depot = depots.find { |entry| entry[:id] == "kaohsiung_north_depot" }
    gangshan_hospital_lat = 22.7807473
    assert_operator north_depot[:lat], :<, gangshan_hospital_lat
    north_link = north_depot[:track_links].sole
    assert_operator north_link[:coordinates].last[1], :<, gangshan_hospital_lat
    refute north_link[:coordinates].any? { |lon, lat| lat > 22.785 },
           "北機廠支線不應延伸到岡山車站以北"

    zuoying = depots.find { |entry| entry[:id] == "hsr_zuoying_depot" }
    xinzuoying_lat = 22.687543335422784
    assert_operator zuoying[:lat], :>, xinzuoying_lat
    zuoying_link = zuoying[:track_links].sole
    assert_operator zuoying_link[:coordinates].last[1], :>, xinzuoying_lat
    assert_operator zuoying_link[:coordinates].first[1], :>, xinzuoying_lat

    south_depot = depots.find { |entry| entry[:id] == "kaohsiung_south_depot" }
    caoya_lat = 22.5805475
    caoya_lon = 120.3287686
    south_link = south_depot[:track_links].sole
    assert_operator south_link[:coordinates].first[1], :>, 22.578
    assert_operator south_link[:coordinates].first[1], :<, 22.582
    assert Geojson::TrackGeometry.planar_distance_meters(
      south_link[:coordinates].first[0],
      south_link[:coordinates].first[1],
      caoya_lon,
      caoya_lat
    ) < 150
  end
end
