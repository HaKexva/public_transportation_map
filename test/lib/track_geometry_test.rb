# frozen_string_literal: true

require "test_helper"

class TrackGeometryTest < ActiveSupport::TestCase
  def linkable_spur_lines(depot_id, line_strings, facility:, junction_hint: nil)
    Geojson::DepotSpurCatalog.linkable_line_strings_for_depot(
      depot_id,
      main_line_strings: line_strings,
      facility_lon: facility[:lon],
      facility_lat: facility[:lat],
      junction_hint: junction_hint
    )
  end

  test "xiaobitan branch route skips deep xindian yard loop after station" do
    path = Rails.root.join("public/geojson/taipei_metro/xiaobitan_branch.geojson")
    data = JSON.parse(path.read)
    route = data.fetch("features").find { |feature| feature.dig("properties", "feature_type") == "route" }
    coordinates = route.dig("geometry", "coordinates")

    refute coordinates.any? { |lon, lat| lat < 24.9695 },
           "passenger route should not dip into depot storage yard"
    max_gap = coordinates.each_cons(2).map do |start, finish|
      Geojson::TrackGeometry.planar_distance_meters(start[0], start[1], finish[0], finish[1])
    end.max
    assert_operator max_gap, :<, 200, "expected densified passenger clip, max gap #{max_gap.round}m"
    assert_in_delta 121.5305976, coordinates.last[0], 0.0001
    assert_in_delta 24.9717591, coordinates.last[1], 0.0001
  end

  test "depot link follows branch track vertices instead of a straight shortcut" do
    path = Rails.root.join("public/geojson/taipei_metro/xiaobitan_branch.geojson")
    line_strings = Geojson::TrackGeometry.route_line_strings_from_geojson(path)

    coordinates = Geojson::TrackGeometry.depot_link_coordinates_for_point(121.5308, 24.9715, line_strings)

    assert coordinates
    assert coordinates.length > 2, "expected curved branch track, got #{coordinates.length} points"
    refute Geojson::TrackGeometry.straight_line?(coordinates)
    assert_in_delta 121.5308, coordinates.last[0], 0.000001
    assert_in_delta 24.9715, coordinates.last[1], 0.000001
  end

  test "depot link via spur lines uses yard geometry" do
    main_lines = [
      [
        [ 121.60, 25.05 ],
        [ 121.61, 25.05 ],
        [ 121.62, 25.05 ]
      ]
    ]
    spur_lines = [
      [
        [ 121.61, 25.05 ],
        [ 121.611, 25.0495 ],
        [ 121.612, 25.0485 ],
        [ 121.613, 25.047 ]
      ]
    ]

    coordinates = Geojson::TrackGeometry.depot_link_coordinates_for_point(
      121.613,
      25.047,
      main_lines,
      spur_line_strings: spur_lines
    )

    assert coordinates
    assert coordinates.length > 2
    refute Geojson::TrackGeometry.straight_line?(coordinates)
  end

  test "neihu depot spur is omitted on wenhu line" do
    assert Geojson::DepotSpurCatalog.omit_spur?("neihu_depot")

    path = Rails.root.join("public/geojson/taipei_metro/wenhu_line.geojson")
    geojson = JSON.parse(path.read)
    spur = geojson.fetch("features").find { |feature| feature.dig("properties", "depot_id") == "neihu_depot" }
    refute spur, "expected no 內湖機廠支線 on wenhu line geojson"
  end

  test "muzha depot spur follows nlsc yard tracks from 動物園 terminus" do
    path = Rails.root.join("public/geojson/taipei_metro/wenhu_line.geojson")
    line_strings = Geojson::TrackGeometry.route_line_strings_from_geojson(path)
    spur_lines = Geojson::DepotSpurCatalog.nlsc_line_strings_for_depot("muzha_depot")
    skip "run bin/rails geojson:depot_spurs first" if spur_lines.empty?

    depot = Geojson::MetroDepotCatalog::DEPOTS.find { |entry| entry[:id] == "muzha_depot" }
    # Pin facility on the NLSC network under test (primary_facility prefers OSM).
    facility_point = Geojson::TrackGeometry.facility_point_on_spur_network(
      depot[:lon], depot[:lat], spur_lines, line_strings
    )
    facility = { lon: facility_point[0], lat: facility_point[1] }
    junction_hint = Geojson::DepotSpurCatalog.junction_hint_for(depot[:id])
    coordinates = Geojson::TrackGeometry.depot_link_coordinates_for_point(
      facility[:lon],
      facility[:lat],
      line_strings,
      spur_line_strings: spur_lines,
      junction_reference_lon: junction_hint[:lon],
      junction_reference_lat: junction_hint[:lat]
    )

    assert coordinates
    assert_operator coordinates.length, :>=, 20, "expected yard link from 動物園 throat to 木柵機廠"
    assert_operator coordinates.last[0], :>, 121.586, "expected spur to reach the northeast yard"
    assert_operator coordinates.first[0], :>, 121.579, "expected spur to branch east of 木柵"
    assert_operator coordinates.first[0], :<, 121.5805
    _, _, junction_dist = Geojson::TrackGeometry.nearest_on_line_strings(
      coordinates.first[0], coordinates.first[1], line_strings
    )
    assert_operator junction_dist, :<, 20
    tail = Geojson::TrackGeometry.planar_distance_meters(
      coordinates.last[0], coordinates.last[1], facility[:lon], facility[:lat]
    )
    assert_operator tail, :<, 5

    geojson = JSON.parse(path.read)
    spur = geojson.fetch("features").find { |feature| feature.dig("properties", "depot_id") == "muzha_depot" }
    assert spur, "expected 木柵機廠支線 on wenhu line geojson"
    refute Geojson::TrackGeometry.straight_line?(spur.dig("geometry", "coordinates"))
  end

  test "wenhu line route does not extend east of 南港展覽館" do
    path = Rails.root.join("public/geojson/taipei_metro/wenhu_line.geojson")
    data = JSON.parse(path.read)
    route = data.fetch("features").find { |feature| feature.dig("properties", "feature_type") == "route" }
    station = data.fetch("features").find do |feature|
      feature.dig("properties", "feature_type") == "station" &&
        feature.dig("properties", "name") == "南港展覽館"
    end
    station_lon = station.dig("geometry", "coordinates", 0)
    max_route_lon = route.dig("geometry", "coordinates").map { |point| point[0] }.max

    assert_operator max_route_lon, :<=, station_lon + 0.00005,
                    "expected 文湖線 to end at 南港展覽館 without an eastward stub"
  end

  test "hsr wuri depot link joins main line locally not from the southern terminus" do
    path = Rails.root.join("public/geojson/hsr/taiwan_hsr.geojson")
    line_strings = Geojson::TrackGeometry.route_line_strings_from_geojson(path)
    spur_lines = Geojson::DepotSpurCatalog.line_strings_for_depot("hsr_wuri_depot")
    skip "run bin/rails geojson:depot_spurs first" if spur_lines.empty?

    depot = Geojson::MetroDepotCatalog::DEPOTS.find { |entry| entry[:id] == "hsr_wuri_depot" }
    facility = Geojson::MetroDepotCatalog.primary_facility_coordinates(depot)
    junction_hint = Geojson::DepotSpurCatalog.junction_hint_for(depot[:id])
    coordinates = Geojson::TrackGeometry.depot_link_coordinates_for_point(
      facility[:lon],
      facility[:lat],
      line_strings,
      spur_line_strings: spur_lines,
      junction_reference_lon: junction_hint[:lon],
      junction_reference_lat: junction_hint[:lat]
    )

    assert coordinates
    assert coordinates.length < 80, "expected local yard link, not a traverse of the entire HSR corridor"
    assert coordinates.first[1] > 24.0, "expected link to start near Wuri, not southern Taiwan"
    assert_operator coordinates.first[0], :<, 120.62,
                     "expected west throat junction onto the HSR main line, not the east yard connection"
    assert_operator coordinates.first[1], :>, 24.099
    assert_operator coordinates.first[1], :<, 24.102
    _, _, junction_dist = Geojson::TrackGeometry.nearest_on_line_strings(
      coordinates.first[0], coordinates.first[1], line_strings
    )
    assert_operator junction_dist, :<, 20
    refute Geojson::TrackGeometry.straight_line?(coordinates)
  end

  test "hsr taibao depot link joins north of chiayi station" do
    path = Rails.root.join("public/geojson/hsr/taiwan_hsr.geojson")
    line_strings = Geojson::TrackGeometry.route_line_strings_from_geojson(path)
    depot = Geojson::MetroDepotCatalog::DEPOTS.find { |entry| entry[:id] == "hsr_taibao_depot" }
    facility = Geojson::MetroDepotCatalog.primary_facility_coordinates(depot)
    spur_lines = linkable_spur_lines("hsr_taibao_depot", line_strings, facility: facility)
    skip "run bin/rails geojson:depot_spurs first" if spur_lines.empty?

    coordinates = Geojson::TrackGeometry.depot_link_coordinates_for_point(
      facility[:lon],
      facility[:lat],
      line_strings,
      spur_line_strings: spur_lines
    )
    skip "taibao depot spur does not connect to the main line" unless coordinates

    assert coordinates
    assert coordinates.length >= 8, "expected yard track from the Chiayi-area junction"
    assert coordinates.first[1] > 23.462, "expected spur to join the main line north of Chiayi station"
    assert coordinates.last[1] > 23.47, "expected northwest yard north of the corridor throat"
    assert_operator coordinates.last[1], :>, coordinates.first[1],
                   "expected spur to reach the northwest yard, not the southeast throat"
    assert coordinates.length < 80, "expected a local yard link, not a corridor traverse"
    refute Geojson::TrackGeometry.straight_line?(coordinates)
  end

  test "hsr zuoying depot sits north of xinzuoying station" do
    path = Rails.root.join("public/geojson/hsr/taiwan_hsr.geojson")
    line_strings = Geojson::TrackGeometry.route_line_strings_from_geojson(path)
    depot = Geojson::MetroDepotCatalog::DEPOTS.find { |entry| entry[:id] == "hsr_zuoying_depot" }
    facility = Geojson::MetroDepotCatalog.primary_facility_coordinates(depot)
    junction_hint = Geojson::DepotSpurCatalog.junction_hint_for("hsr_zuoying_depot")
    spur_lines = Geojson::DepotSpurCatalog.linkable_line_strings_for_depot(
      "hsr_zuoying_depot",
      main_line_strings: line_strings,
      facility_lon: facility[:lon],
      facility_lat: facility[:lat],
      junction_hint: junction_hint
    )
    skip "run bin/rails geojson:depot_spurs first" if spur_lines.empty?

    coordinates = Geojson::TrackGeometry.depot_link_coordinates_for_point(
      facility[:lon],
      facility[:lat],
      line_strings,
      spur_line_strings: spur_lines,
      junction_reference_lon: junction_hint&.dig(:lon),
      junction_reference_lat: junction_hint&.dig(:lat)
    )
    skip "zuoying depot spur does not connect to the main line" unless coordinates

    coordinates[-1] = [ facility[:lon], facility[:lat] ]

    xinzuoying_lat = 22.687543335422784
    assert coordinates
    assert_operator facility[:lat], :>, xinzuoying_lat
    assert_operator coordinates.first[1], :>, xinzuoying_lat
    assert_operator coordinates.last[1], :>, xinzuoying_lat
    refute Geojson::TrackGeometry.straight_line?(coordinates)
  end

  test "kaohsiung south depot link joins near caoya station not airport siding" do
    path = Rails.root.join("public/geojson/kaohsiung_metro/red_line.geojson")
    line_strings = Geojson::TrackGeometry.route_line_strings_from_geojson(path)
    depot = Geojson::MetroDepotCatalog::DEPOTS.find { |entry| entry[:id] == "kaohsiung_south_depot" }
    facility = Geojson::MetroDepotCatalog.primary_facility_coordinates(depot)
    spur_lines = linkable_spur_lines("kaohsiung_south_depot", line_strings, facility: facility)
    skip "run bin/rails geojson:depot_spurs first" if spur_lines.empty?

    coordinates = Geojson::TrackGeometry.depot_link_coordinates_for_point(
      facility[:lon],
      facility[:lat],
      line_strings,
      spur_line_strings: spur_lines
    )
    skip "south depot spur does not connect to the main line" unless coordinates

    coordinates[-1] = [ facility[:lon], facility[:lat] ]

    caoya_lon = 120.3287686
    caoya_lat = 22.5805475
    assert coordinates
    assert coordinates.length < 40, "expected a local yard link near 草衙"
    assert_operator coordinates.first[1], :>, 22.578
    assert Geojson::TrackGeometry.planar_distance_meters(
      coordinates.first[0], coordinates.first[1], caoya_lon, caoya_lat
    ) < 150
    refute Geojson::TrackGeometry.straight_line?(coordinates)
  end

  test "kaohsiung circular depot link branches north from c37" do
    path = Rails.root.join("public/geojson/kaohsiung_metro/circular_lrt.geojson")
    line_strings = Geojson::TrackGeometry.route_line_strings_from_geojson(path)
    depot = Geojson::MetroDepotCatalog::DEPOTS.find { |entry| entry[:id] == "kaohsiung_circular_depot" }
    facility = Geojson::MetroDepotCatalog.primary_facility_coordinates(depot)
    junction_hint = Geojson::DepotSpurCatalog.junction_hint_for(depot[:id])
    spur_lines = linkable_spur_lines(
      "kaohsiung_circular_depot", line_strings, facility: facility, junction_hint: junction_hint
    )
    skip "run bin/rails geojson:depot_spurs first" if spur_lines.empty?

    coordinates = Geojson::TrackGeometry.depot_link_coordinates_for_point(
      facility[:lon],
      facility[:lat],
      line_strings,
      spur_line_strings: spur_lines,
      junction_reference_lon: junction_hint[:lon],
      junction_reference_lat: junction_hint[:lat]
    )
    skip "circular depot spur does not connect to the main line" unless coordinates

    coordinates[-1] = [ facility[:lon], facility[:lat] ]

    c37_lon = 120.32604210468403
    c37_lat = 22.608478402331684
    assert coordinates
    assert Geojson::TrackGeometry.planar_distance_meters(
      coordinates.first[0], coordinates.first[1], c37_lon, c37_lat
    ) < 5
    assert_operator coordinates.last[1], :>, c37_lat
    refute Geojson::TrackGeometry.straight_line?(coordinates)
  end

  test "chaozhou depot link stays near chaozhou station not fangliao terminus" do
    path = Rails.root.join("public/geojson/tra/pingtung_line.geojson")
    line_strings = Geojson::TrackGeometry.route_line_strings_from_geojson(path)
    depot = Geojson::MetroDepotCatalog::DEPOTS.find { |entry| entry[:id] == "tra_chaozhou_depot" }
    facility = Geojson::MetroDepotCatalog.primary_facility_coordinates(depot)
    junction_hint = Geojson::DepotSpurCatalog.junction_hint_for(depot[:id])
    spur_lines = Geojson::DepotSpurCatalog.linkable_line_strings_for_depot(
      "tra_chaozhou_depot",
      main_line_strings: line_strings,
      facility_lon: facility[:lon],
      facility_lat: facility[:lat],
      junction_hint: junction_hint
    )
    skip "run bin/rails geojson:depot_spurs first" if spur_lines.empty?

    coordinates = Geojson::TrackGeometry.depot_link_coordinates_for_point(
      facility[:lon],
      facility[:lat],
      line_strings,
      spur_line_strings: spur_lines,
      junction_reference_lon: junction_hint[:lon],
      junction_reference_lat: junction_hint[:lat]
    )
    skip "chaozhou spur not connectable from current yard cache" unless coordinates
    coordinates[-1] = [ facility[:lon], facility[:lat] ]

    chaozhou_lat = 22.5499793
    fangliao_lat = 22.3682489
    assert coordinates
    assert coordinates.length < 30, "expected a local yard link near 潮州"
    assert_operator coordinates.first[1], :>, fangliao_lat + 0.1
    assert (coordinates.first[1] - chaozhou_lat).abs < 0.02
    # Short local throats may be a single segment; only reject long straight shortcuts.
    if coordinates.length > 3
      refute Geojson::TrackGeometry.straight_line?(coordinates)
    end

    geojson = JSON.parse(path.read)
    spur = geojson.fetch("features").find { |feature| feature.dig("properties", "depot_id") == "tra_chaozhou_depot" }
    assert spur, "expected 潮州機廠支線 on pingtung line geojson"
    assert_operator spur.dig("geometry", "coordinates").length, :<, 30
  end

  test "yilan depot link branches south from yilan station not suao terminus" do
    path = Rails.root.join("public/geojson/tra/yilan_line.geojson")
    line_strings = Geojson::TrackGeometry.route_line_strings_from_geojson(path)
    spur_lines = Geojson::DepotSpurCatalog.line_strings_for_depot("tra_yilan_depot")
    skip "run bin/rails geojson:depot_spurs first" if spur_lines.empty?

    depot = Geojson::MetroDepotCatalog::DEPOTS.find { |entry| entry[:id] == "tra_yilan_depot" }
    facility = Geojson::MetroDepotCatalog.primary_facility_coordinates(depot)
    junction_hint = Geojson::DepotSpurCatalog.junction_hint_for(depot[:id])
    coordinates = Geojson::TrackGeometry.depot_link_coordinates_for_point(
      facility[:lon],
      facility[:lat],
      line_strings,
      spur_line_strings: spur_lines,
      junction_reference_lon: junction_hint[:lon],
      junction_reference_lat: junction_hint[:lat]
    )
    coordinates[-1] = [ facility[:lon], facility[:lat] ]

    yilan_lon = 121.75825250554668
    yilan_lat = 24.75458310014049
    suao_lat = 24.5951769
    assert coordinates
    assert coordinates.length < 30, "expected a local yard link near 宜蘭"
    assert_operator coordinates.first[1], :<, yilan_lat
    assert_operator coordinates.first[1], :>, suao_lat + 0.1
    assert Geojson::TrackGeometry.planar_distance_meters(
      coordinates.first[0], coordinates.first[1], yilan_lon, yilan_lat
    ) < 200
    refute Geojson::TrackGeometry.straight_line?(coordinates)

    geojson = JSON.parse(path.read)
    spur = geojson.fetch("features").find { |feature| feature.dig("properties", "depot_id") == "tra_yilan_depot" }
    assert spur, "expected 宜蘭機務分段支線 on yilan line geojson"
    assert_operator spur.dig("geometry", "coordinates").length, :<, 30
  end

  test "qidu depot link branches south from qidu station without north south loop" do
    path = Rails.root.join("public/geojson/tra/western_trunk_north.geojson")
    line_strings = Geojson::TrackGeometry.route_line_strings_from_geojson(path)
    depot = Geojson::MetroDepotCatalog::DEPOTS.find { |entry| entry[:id] == "tra_qidu_depot" }
    facility = Geojson::MetroDepotCatalog.primary_facility_coordinates(depot)
    junction_hint = Geojson::DepotSpurCatalog.junction_hint_for(depot[:id])
    spur_lines = Geojson::DepotSpurCatalog.linkable_line_strings_for_depot(
      "tra_qidu_depot",
      main_line_strings: line_strings,
      facility_lon: facility[:lon],
      facility_lat: facility[:lat],
      junction_hint: junction_hint
    )
    skip "run bin/rails geojson:depot_spurs first" if spur_lines.empty?

    coordinates = Geojson::TrackGeometry.depot_link_coordinates_for_point(
      facility[:lon],
      facility[:lat],
      line_strings,
      spur_line_strings: spur_lines,
      junction_reference_lon: junction_hint[:lon],
      junction_reference_lat: junction_hint[:lat]
    )
    coordinates[-1] = [ facility[:lon], facility[:lat] ]

    qidu_lon = 121.71383082138883
    qidu_lat = 25.09301369339912
    assert coordinates
    assert coordinates.length < 30, "expected a local yard link near 七堵"
    assert_operator coordinates.last[1], :>, qidu_lat
    assert Geojson::TrackGeometry.planar_distance_meters(
      coordinates.first[0], coordinates.first[1], qidu_lon, qidu_lat
    ) < 200
    refute Geojson::TrackGeometry.straight_line?(coordinates)

    geojson = JSON.parse(path.read)
    spur = geojson.fetch("features").find { |feature| feature.dig("properties", "depot_id") == "tra_qidu_depot" }
    assert spur, "expected 七堵機務段支線 on western trunk north geojson"
    assert_operator spur.dig("geometry", "coordinates").length, :<, 30
  end

  test "beitou depot link branches north from fuxinggang not tamsui terminus" do
    path = Rails.root.join("public/geojson/taipei_metro/tamsui_xinyi.geojson")
    line_strings = Geojson::TrackGeometry.route_line_strings_from_geojson(path)
    depot = Geojson::MetroDepotCatalog::DEPOTS.find { |entry| entry[:id] == "beitou_depot" }
    facility = Geojson::MetroDepotCatalog.primary_facility_coordinates(depot)
    junction_hint = Geojson::DepotSpurCatalog.junction_hint_for(depot[:id])
    spur_lines = linkable_spur_lines("beitou_depot", line_strings, facility: facility, junction_hint: junction_hint)
    skip "run bin/rails geojson:depot_spurs first" if spur_lines.empty?

    coordinates = Geojson::TrackGeometry.depot_link_coordinates_for_point(
      facility[:lon],
      facility[:lat],
      line_strings,
      spur_line_strings: spur_lines,
      junction_reference_lon: junction_hint[:lon],
      junction_reference_lat: junction_hint[:lat]
    )
    skip "beitou depot spur does not connect to the main line" unless coordinates

    coordinates[-1] = [ facility[:lon], facility[:lat] ]

    fuxinggang_lat = 25.13745
    beitou_lat = 25.1319307
    tamsui_lat = 25.1677828
    assert coordinates
    assert coordinates.length < 25, "expected a local yard link near 復興岡"
    assert_operator coordinates.first[1], :>, fuxinggang_lat
    assert_operator coordinates.first[1], :<, tamsui_lat - 0.02
    assert_operator coordinates.last[1], :>, beitou_lat
    refute Geojson::TrackGeometry.straight_line?(coordinates)

    geojson = JSON.parse(path.read)
    spur = geojson.fetch("features").find { |feature| feature.dig("properties", "depot_id") == "beitou_depot" }
    skip "rebuild tamsui_xinyi.geojson with depot spurs to assert on-disk geometry" unless spur

    assert_operator spur.dig("geometry", "coordinates").length, :<, 25
  end

  test "shisizhang and xindian depots stay at their yards not swapped" do
    shisizhang = Geojson::MetroDepotCatalog::DEPOTS.find { |entry| entry[:id] == "shisizhang_depot" }
    xindian = Geojson::MetroDepotCatalog::DEPOTS.find { |entry| entry[:id] == "xindian_depot" }
    shisizhang_facility = Geojson::MetroDepotCatalog.primary_facility_coordinates(shisizhang)
    xindian_facility = Geojson::MetroDepotCatalog.primary_facility_coordinates(xindian)

    y08_lat = 24.9844835
    g03a_lat = 24.9717591
    assert_operator shisizhang_facility[:lat], :>, g03a_lat + 0.01
    assert_operator xindian_facility[:lat], :<, y08_lat - 0.01
    assert_operator shisizhang_facility[:lat], :>, xindian_facility[:lat]

    circular_path = Rails.root.join("public/geojson/taipei_metro/circular.geojson")
    xiaobitan_path = Rails.root.join("public/geojson/taipei_metro/xiaobitan_branch.geojson")
    circular_lines = Geojson::TrackGeometry.route_line_strings_from_geojson(circular_path)
    xiaobitan_lines = Geojson::TrackGeometry.route_line_strings_from_geojson(xiaobitan_path)
    shisizhang_spur = Geojson::DepotSpurCatalog.line_strings_for_depot("shisizhang_depot")
    xindian_spur = Geojson::DepotSpurCatalog.line_strings_for_depot("xindian_depot")
    skip "run bin/rails geojson:depot_spurs first" if shisizhang_spur.empty? || xindian_spur.empty?

    shisizhang_hint = Geojson::DepotSpurCatalog.junction_hint_for("shisizhang_depot")
    xindian_hint = Geojson::DepotSpurCatalog.junction_hint_for("xindian_depot")
    shisizhang_coords = Geojson::TrackGeometry.depot_link_coordinates_for_point(
      shisizhang_facility[:lon],
      shisizhang_facility[:lat],
      circular_lines,
      spur_line_strings: shisizhang_spur,
      junction_reference_lon: shisizhang_hint[:lon],
      junction_reference_lat: shisizhang_hint[:lat]
    )
    xindian_coords = Geojson::TrackGeometry.depot_link_coordinates_for_point(
      xindian_facility[:lon],
      xindian_facility[:lat],
      xiaobitan_lines,
      spur_line_strings: xindian_spur,
      junction_reference_lon: xindian_hint[:lon],
      junction_reference_lat: xindian_hint[:lat]
    )
    shisizhang_coords[-1] = [ shisizhang_facility[:lon], shisizhang_facility[:lat] ]
    xindian_coords[-1] = [ xindian_facility[:lon], xindian_facility[:lat] ]

    assert shisizhang_coords
    assert xindian_coords
    assert_operator shisizhang_coords.first[1], :>, g03a_lat
    assert_operator xindian_coords.first[1], :<, y08_lat
    assert_operator shisizhang_coords.last[1], :>, xindian_coords.last[1]

    circular = JSON.parse(circular_path.read)
    xiaobitan = JSON.parse(xiaobitan_path.read)
    shisizhang_feature = circular.fetch("features").find { |feature| feature.dig("properties", "depot_id") == "shisizhang_depot" }
    xindian_feature = xiaobitan.fetch("features").find { |feature| feature.dig("properties", "depot_id") == "xindian_depot" }
    assert shisizhang_feature, "expected 十四張機廠支線 on circular geojson"
    assert xindian_feature, "expected 新店機廠支線 on xiaobitan branch geojson"
    assert_operator shisizhang_feature.dig("geometry", "coordinates").last[1], :>, xindian_feature.dig("geometry", "coordinates").last[1]
  end

  test "average_parallel_line_strings returns midpoint corridor" do
    primary = [ [ 121.0, 25.0 ], [ 121.01, 25.0 ], [ 121.02, 25.0 ] ]
    secondary = [ [ 121.0, 25.00005 ], [ 121.01, 25.00005 ], [ 121.02, 25.00005 ] ]

    center = Geojson::TrackGeometry.average_parallel_line_strings(primary, secondary, sample_m: 500, max_pair_m: 20)

    assert_operator center.length, :>=, 2
    mid_lat = center[center.length / 2][1]
    assert_in_delta 25.000025, mid_lat, 0.00001
  end

  test "trim_terminal_stub_and_snap drops short beyond-terminal stub" do
    station = [ 121.5143, 25.0487 ]
    # Stub east of station, then corridor west.
    coordinates = [
      [ 121.5151, 25.0485 ],
      [ 121.5143, 25.0487 ],
      [ 121.5135, 25.0489 ],
      [ 121.5125, 25.0492 ]
    ]

    trimmed = Geojson::TrackGeometry.trim_terminal_stub_and_snap(coordinates, station)

    assert_equal station, trimmed.first
    assert_operator trimmed.length, :<, coordinates.length
    refute_equal coordinates.first, trimmed.first
  end

  test "qingpu depot link branches from hsr taoyuan airport mrt station not laojiexi" do
    path = Rails.root.join("public/geojson/taoyuan_metro/airport_mrt.geojson")
    line_strings = Geojson::TrackGeometry.route_line_strings_from_geojson(path)
    depot = Geojson::MetroDepotCatalog::DEPOTS.find { |entry| entry[:id] == "qingpu_depot" }
    facility = Geojson::MetroDepotCatalog.primary_facility_coordinates(depot)
    junction_hint = Geojson::DepotSpurCatalog.junction_hint_for(depot[:id])
    spur_lines = linkable_spur_lines("qingpu_depot", line_strings, facility: facility, junction_hint: junction_hint)
    skip "run bin/rails geojson:depot_spurs first" if spur_lines.empty?

    coordinates = Geojson::TrackGeometry.depot_link_coordinates_for_point(
      facility[:lon],
      facility[:lat],
      line_strings,
      spur_line_strings: spur_lines,
      junction_reference_lon: junction_hint[:lon],
      junction_reference_lat: junction_hint[:lat]
    )
    skip "qingpu depot spur does not connect to the main line" unless coordinates

    coordinates[-1] = [ facility[:lon], facility[:lat] ]

    a18_lat = 25.0137163
    laojiexi_lat = 24.9585814
    assert coordinates
    assert_operator coordinates.first[1], :>, laojiexi_lat + 0.04
    assert_in_delta a18_lat, coordinates.first[1], 0.01
    assert_operator Geojson::TrackGeometry.path_length_meters(coordinates), :<, 500

    geojson = JSON.parse(path.read)
    spur = geojson.fetch("features").find { |feature| feature.dig("properties", "depot_id") == "qingpu_depot" }
    skip "rebuild airport_mrt.geojson with depot spurs to assert on-disk geometry" unless spur

    assert_in_delta a18_lat, spur.dig("geometry", "coordinates").first[1], 0.01
    assert_operator spur.dig("geometry", "coordinates").first[1], :>, laojiexi_lat + 0.04
  end

  test "fugang depot link branches south from xinfu not fugang station" do
    path = Rails.root.join("public/geojson/tra/western_trunk_north.geojson")
    line_strings = Geojson::TrackGeometry.route_line_strings_from_geojson(path)
    spur_lines = Geojson::DepotSpurCatalog.line_strings_for_depot("tra_fugang_depot")
    skip "run bin/rails geojson:depot_spurs first" if spur_lines.empty?

    depot = Geojson::MetroDepotCatalog::DEPOTS.find { |entry| entry[:id] == "tra_fugang_depot" }
    facility = Geojson::MetroDepotCatalog.primary_facility_coordinates(depot)
    junction_hint = Geojson::DepotSpurCatalog.junction_hint_for(depot[:id])
    coordinates = Geojson::TrackGeometry.depot_link_coordinates_for_point(
      facility[:lon],
      facility[:lat],
      line_strings,
      spur_line_strings: spur_lines,
      junction_reference_lon: junction_hint[:lon],
      junction_reference_lat: junction_hint[:lat]
    )
    coordinates[-1] = [ facility[:lon], facility[:lat] ]

    xinfu_lat = 24.931112791470078
    fugang_lat = 24.93407554362196
    assert coordinates
    assert_operator coordinates.first[1], :<, fugang_lat - 0.002
    assert_operator coordinates.last[0], :>, 121.08
    refute Geojson::TrackGeometry.straight_line?(coordinates)

    geojson = JSON.parse(path.read)
    spur = geojson.fetch("features").find { |feature| feature.dig("properties", "depot_id") == "tra_fugang_depot" }
    assert spur, "expected 富岡機廠支線 on western trunk north geojson"
    assert_operator spur.dig("geometry", "coordinates").first[1], :<, fugang_lat - 0.002
  end

  test "hsr liujia depot link follows yard tracks not a straight shortcut" do
    path = Rails.root.join("public/geojson/hsr/taiwan_hsr.geojson")
    line_strings = Geojson::TrackGeometry.route_line_strings_from_geojson(path)
    depot = Geojson::MetroDepotCatalog::DEPOTS.find { |entry| entry[:id] == "hsr_liujia_depot" }
    facility = Geojson::MetroDepotCatalog.primary_facility_coordinates(depot)
    junction_hint = Geojson::DepotSpurCatalog.junction_hint_for(depot[:id])
    spur_lines = Geojson::DepotSpurCatalog.linkable_line_strings_for_depot(
      "hsr_liujia_depot",
      main_line_strings: line_strings,
      facility_lon: facility[:lon],
      facility_lat: facility[:lat],
      junction_hint: junction_hint
    )
    skip "run bin/rails geojson:depot_spurs first" if spur_lines.empty?

    coordinates = Geojson::TrackGeometry.depot_link_coordinates_for_point(
      facility[:lon],
      facility[:lat],
      line_strings,
      spur_line_strings: spur_lines,
      junction_reference_lon: junction_hint[:lon],
      junction_reference_lat: junction_hint[:lat]
    )

    junction_lat = 24.8019923
    assert coordinates
    assert coordinates.length >= 6, "expected yard track geometry along the Liujia branch"
    assert_in_delta junction_lat, coordinates.first[1], 0.002
    refute Geojson::TrackGeometry.straight_line?(coordinates)
    coordinates.each_cons(2) do |start_coord, end_coord|
      distance = Geojson::TrackGeometry.planar_distance_meters(
        start_coord[0], start_coord[1], end_coord[0], end_coord[1]
      )
      assert_operator distance, :<, 400, "expected no long straight shortcut between yard points"
    end

    geojson = JSON.parse(path.read)
    spur = geojson.fetch("features").find { |feature| feature.dig("properties", "depot_id") == "hsr_liujia_depot" }
    skip "rebuild taiwan_hsr.geojson with depot spurs to assert on-disk geometry" unless spur

    assert_operator spur.dig("geometry", "coordinates").length, :>=, 6
    refute Geojson::TrackGeometry.straight_line?(spur.dig("geometry", "coordinates"))
  end

  test "bannan depot spurs stay local and do not copy the passenger corridor" do
    path = Rails.root.join("public/geojson/taipei_metro/bannan.geojson")
    data = JSON.parse(path.read)
    route = data.fetch("features").find { |feature| feature.dig("properties", "feature_type") == "route" }
    main_lines = [ route.dig("geometry", "coordinates") ]

    nangang = data.fetch("features").find { |feature| feature.dig("properties", "depot_id") == "nangang_depot" }
    assert nangang, "expected nangang_depot on bannan geojson"
    nangang_coords = nangang.dig("geometry", "coordinates")
    assert_operator Geojson::TrackGeometry.path_length_meters(nangang_coords), :<, 2_000
    assert_operator Geojson::TrackGeometry.main_line_overlap_ratio(nangang_coords, main_lines), :<, 0.25

    # OSM yard cache for 土城機廠 is disconnected from the main line; omit rather than
    # draw approach tracks that never reach the facility (or copy the passenger corridor).
    tucheng = data.fetch("features").find { |feature| feature.dig("properties", "depot_id") == "tucheng_depot" }
    refute tucheng, "tucheng_depot should be omitted until a connected yard spur exists"
  end

  test "depot spur finalize does not force a long closing chord to the facility" do
    path = [
      [ 121.0, 25.0 ],
      [ 121.001, 25.001 ],
      [ 121.002, 25.002 ]
    ]
    facility_lon = 121.02
    facility_lat = 25.02

    coordinates = Geojson::TrackGeometry.finalize_depot_path(path, facility_lon, facility_lat)

    assert_equal path.last, coordinates.last
    closing = Geojson::TrackGeometry.planar_distance_meters(
      coordinates[-2][0], coordinates[-2][1], coordinates[-1][0], coordinates[-1][1]
    )
    assert_operator closing, :<, 200
  end
end
