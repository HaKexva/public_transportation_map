# frozen_string_literal: true

require "test_helper"

class GeojsonBusImporterTest < ActiveSupport::TestCase
  class FakeTdxClient
    def initialize(payloads)
      @payloads = payloads
    end

    def configured?
      true
    end

    def fetch_all(path)
      @payloads.fetch(path)
    end
  end

  test "matches 1xx and 2xx names including letter suffixes" do
    keelung = Geojson::BusCatalog.find("Keelung")
    assert Geojson::BusImporter.series_match?("101", series: "1", city: keelung)
    assert Geojson::BusImporter.series_match?("103區", series: "1", city: keelung)
    refute Geojson::BusImporter.series_match?("11", series: "1", city: keelung)
    refute Geojson::BusImporter.series_match?("201", series: "1", city: keelung)
    assert Geojson::BusImporter.series_match?("201", series: "2", city: keelung)
    assert Geojson::BusImporter.series_match?("205區", series: "2", city: keelung)
    refute Geojson::BusImporter.series_match?("21", series: "2", city: keelung)
    refute Geojson::BusImporter.series_match?("101", series: "2", city: keelung)
    assert Geojson::BusImporter.series_match?("301", series: "3", city: keelung)
    assert Geojson::BusImporter.series_match?("3014", series: "3", city: keelung)
    refute Geojson::BusImporter.series_match?("201", series: "3", city: keelung)
    assert_equal "301", Geojson::BusImporter.public_ref("3014", city: keelung)
    assert_equal "1717", Geojson::BusImporter.public_ref("1717", city: keelung)
    assert_equal "5014", Geojson::BusImporter.public_ref("5014", city: Geojson::BusCatalog.find("Taoyuan"))
    assert_equal "101", Geojson::BusImporter.public_ref("101", city: keelung)
    assert Geojson::BusImporter.extra_digit_name?("3014")
    refute Geojson::BusImporter.extra_digit_name?("301")
    assert_equal "中山一路", Geojson::BusImporter.unlabeled_trunk_via(%w[中山一路 成功市場 高遠新村])
    assert_nil Geojson::BusImporter.unlabeled_trunk_via(%w[祥豐街 中正路])
    assert_equal "祥豐街", Geojson::BusImporter.variant_label("SubRoutes" => [ { "Headsign" => "和平島—經祥豐街" } ])
    assert_equal "中正路", Geojson::BusImporter.variant_label("SubRoutes" => [ { "Headsign" => "和平島—經中正路" } ])
    assert_equal "美的世界、八斗山莊", Geojson::BusImporter.variant_label(
      "SubRoutes" => [ { "Headsign" => "八斗子—經美的世界(經八斗山莊)" } ]
    )
    assert Geojson::BusImporter.series_match?("4081", series: "4", city: keelung)
    assert Geojson::BusImporter.series_match?("4101", series: "4", city: keelung)
    refute Geojson::BusImporter.series_match?("4081", series: "1", city: keelung)
  end

  test "ref_slug keeps color-coded and Chinese route names distinct" do
    assert_equal "32", Geojson::BusImporter.ref_slug("32")
    assert_equal "hong32", Geojson::BusImporter.ref_slug("紅32")
    assert_equal "lan1", Geojson::BusImporter.ref_slug("藍1")
    assert_equal "shimin1", Geojson::BusImporter.ref_slug("市民1")
    refute_equal Geojson::BusImporter.ref_slug("紅32"), Geojson::BusImporter.ref_slug("32")
    refute_equal Geojson::BusImporter.ref_slug("內湖幹線"), Geojson::BusImporter.ref_slug("紅32")
    assert_match(/\Aganxian_[0-9a-f]{10}\z/, Geojson::BusImporter.ref_slug("內湖幹線"))
  end

  test "imports Keelung city bus geometry and stop points without operator fields" do
    client = FakeTdxClient.new(
      "v2/Bus/Route/City/Keelung" => [ route_record ],
      "v2/Bus/Shape/City/Keelung" => [ shape_record ],
      "v2/Bus/StopOfRoute/City/Keelung" => [ stop_of_route_record ]
    )

    result = Geojson::BusImporter.import!(
      city_id: "Keelung",
      series: "9",
      client: client,
      rewrite_manifest: false
    )

    path = Geojson::BusLayout.geojson_path(city_id: "Keelung", slug: "keelung_901", ref: "901")
    assert_equal [ "keelung_901" ], result.routes
    assert path.exist?

    data = JSON.parse(path.read)
    assert_equal "Keelung", data.dig("properties", "city_id")
    assert_equal "901", data.dig("properties", "ref")
    assert_match(/\A#[0-9A-Fa-f]{6}\z/, data.dig("properties", "color"))
    assert_nil data.dig("properties", "operator_id")
    assert data["features"].any? { |feature| feature.dig("geometry", "type") == "LineString" }
    station = data["features"].find { |feature| feature.dig("properties", "feature_type") == "station" }
    assert station
    assert_equal "KELST01", station.dig("properties", "station_id")
  ensure
    remove_keelung_fixture("keelung_901")
  end

  test "marks dispatch yards with stop_role depot" do
    client = FakeTdxClient.new(
      "v2/Bus/Route/City/Keelung" => [ route_record ],
      "v2/Bus/Shape/City/Keelung" => [ shape_record ],
      "v2/Bus/StopOfRoute/City/Keelung" => [
        stop_of_route_record(stop_name: "暖暖分站(調度站)", station_id: "KELDEPOT")
      ]
    )

    Geojson::BusImporter.import!(
      city_id: "Keelung",
      series: "9",
      client: client,
      rewrite_manifest: false
    )

    data = JSON.parse(Geojson::BusLayout.geojson_path(city_id: "Keelung", slug: "keelung_901", ref: "901").read)
    station = data["features"].find { |feature| feature.dig("properties", "feature_type") == "station" }
    assert_equal "depot", station.dig("properties", "stop_role")
    assert Geojson::BusImporter.depot_stop_name?("東南客運停車場")
    assert Geojson::BusImporter.depot_stop_name?("中壢總站")
    assert Geojson::BusImporter.depot_stop_name?("三重客運五股站")
    assert Geojson::BusImporter.depot_stop_name?("八斗子分站")
    refute Geojson::BusImporter.depot_stop_name?("立體停車場(五股公有市場)")
    refute Geojson::BusImporter.depot_stop_name?("南港機廠")
    refute Geojson::BusImporter.depot_stop_name?("安坑輕軌機廠")
    refute Geojson::BusImporter.depot_stop_name?("高鐵總機廠")
    refute Geojson::BusImporter.depot_stop_name?("捷運北屯總站(敦富路)")
    refute Geojson::BusImporter.depot_stop_name?("總站")
  ensure
    remove_keelung_fixture("keelung_901")
  end

  test "imports every route when series is omitted" do
    client = FakeTdxClient.new(
      "v2/Bus/Route/City/Keelung" => [ route_record, route_record(uid: "KEL902", name: "902") ],
      "v2/Bus/Shape/City/Keelung" => [
        shape_record,
        shape_record(uid: "KEL902", wkt: "LINESTRING(121.74 25.13, 121.75 25.12)")
      ],
      "v2/Bus/StopOfRoute/City/Keelung" => [
        stop_of_route_record,
        stop_of_route_record(uid: "KEL902", stop_uid: "KEL2001")
      ]
    )

    result = Geojson::BusImporter.import!(
      city_id: "Keelung",
      client: client,
      rewrite_manifest: false
    )

    assert_includes result.routes, "keelung_901"
    assert_includes result.routes, "keelung_902"
  ensure
    remove_keelung_fixture("keelung_901", "keelung_902")
  end

  test "keeps both direction polylines and direction on stops" do
    client = FakeTdxClient.new(
      "v2/Bus/Route/City/Keelung" => [ route_record(map_url: "https://example.test/101.png") ],
      "v2/Bus/Shape/City/Keelung" => [
        shape_record,
        shape_record(direction: 1, wkt: "LINESTRING(121.739 25.1322, 121.744 25.1282)")
      ],
      "v2/Bus/StopOfRoute/City/Keelung" => [
        stop_of_route_record.merge("Direction" => 0),
        stop_of_route_record(stop_uid: "KEL1002").merge("Direction" => 1)
      ]
    )

    Geojson::BusImporter.import!(
      city_id: "Keelung",
      series: "9",
      client: client,
      rewrite_manifest: false
    )

    data = JSON.parse(Geojson::BusLayout.geojson_path(city_id: "Keelung", slug: "keelung_901", ref: "901").read)
    line_features = data["features"].select { |feature| feature.dig("properties", "feature_type") == "route" }
    stations = data["features"].select { |feature| feature.dig("properties", "feature_type") == "station" }

    assert_equal 2, line_features.length
    assert_equal [ 0, 1 ], line_features.map { |feature| feature.dig("properties", "direction") }.sort
    assert_equal "https://example.test/101.png", data.dig("properties", "official_map_url")
    assert_equal [ 0, 1 ], stations.map { |feature| feature.dig("properties", "direction") }.sort
  ensure
    remove_keelung_fixture("keelung_901")
  end

  test "keeps 101 Xiangfeng and Zhongzheng variants and drops extra-digit ghosts" do
    client = FakeTdxClient.new(
      "v2/Bus/Route/City/Keelung" => [
        route_record(uid: "KEL991A", name: "991", headsign: "和平島—經中正路"),
        route_record(uid: "KEL991B", name: "991", headsign: "和平島—經祥豐街"),
        route_record(uid: "KEL3014", name: "9914", headsign: "太白莊→經太平青鳥")
      ],
      "v2/Bus/Shape/City/Keelung" => [
        shape_record(uid: "KEL991A"),
        shape_record(uid: "KEL991B", wkt: "LINESTRING(121.75 25.14, 121.76 25.15)"),
        shape_record(uid: "KEL3014", wkt: "LINESTRING(121.73 25.13, 121.74 25.14)")
      ],
      "v2/Bus/StopOfRoute/City/Keelung" => [
        stop_of_route_record(uid: "KEL991A"),
        stop_of_route_record(uid: "KEL991B", stop_uid: "KEL991B1"),
        stop_of_route_record(uid: "KEL3014", stop_uid: "KEL30141")
      ]
    )

    result = Geojson::BusImporter.import!(
      city_id: "Keelung",
      client: client,
      rewrite_manifest: false
    )

    assert_equal %w[keelung_991_xiangfeng keelung_991_zhongzheng].sort, result.routes.sort

    zhongzheng = JSON.parse(Geojson::BusLayout.find_geojson("keelung_991_zhongzheng").read)
    assert_equal "991", zhongzheng.dig("properties", "ref")
    assert_equal "中正路", zhongzheng.dig("properties", "via")
    assert_includes zhongzheng.dig("properties", "name"), "中正路"
  ensure
    result&.routes&.each { |slug| remove_keelung_fixture(slug) }
  end

  test "keeps Keelung 301 original plus two detours and drops 3014" do
    client = FakeTdxClient.new(
      "v2/Bus/Route/City/Keelung" => [
        route_record(uid: "KEE0318", name: "301", headsign: "太白莊—經成功市場"),
        route_record(uid: "KEE0325", name: "3014", headsign: "太白莊→經太平青鳥"),
        route_record(uid: "KEE0381", name: "301", headsign: "太白莊→經中山一路"),
        route_record(uid: "KEE0389", name: "301", headsign: "太白莊→經高遠新村")
      ],
      "v2/Bus/Shape/City/Keelung" => [
        shape_record(uid: "KEE0318", wkt: "LINESTRING(121.74 25.13, 121.75 25.12)"),
        shape_record(uid: "KEE0325", wkt: "LINESTRING(121.73 25.13, 121.74 25.14)"),
        shape_record(uid: "KEE0381"),
        shape_record(uid: "KEE0389", wkt: "LINESTRING(121.75 25.14, 121.76 25.15)")
      ],
      "v2/Bus/StopOfRoute/City/Keelung" => [
        stop_of_route_record(uid: "KEE0318", stop_uid: "KEE03181"),
        stop_of_route_record(uid: "KEE0325", stop_uid: "KEE03251"),
        stop_of_route_record(uid: "KEE0381"),
        stop_of_route_record(uid: "KEE0389", stop_uid: "KEE03891")
      ]
    )

    result = Geojson::BusImporter.import!(
      city_id: "Keelung",
      client: client,
      rewrite_manifest: false
    )

    assert_includes result.routes, "keelung_301"
    refute result.routes.any? { |slug| slug.include?("be8a74ee1e") }
    assert_equal 3, result.routes.length

    original = JSON.parse(Geojson::BusLayout.find_geojson("keelung_301").read)
    assert_equal "301", original.dig("properties", "name")
    assert_nil original.dig("properties", "via")

    detours = result.routes.reject { |slug| slug == "keelung_301" }.sort.map do |slug|
      JSON.parse(Geojson::BusLayout.find_geojson(slug).read).dig("properties", "via")
    end
    assert_equal %w[成功市場 高遠新村].sort, detours.sort
  ensure
    result&.routes&.each { |slug| remove_keelung_fixture(slug) }
  end

  test "keeps extra-digit detours when the 3-digit parent has only one path" do
    client = FakeTdxClient.new(
      "v2/Bus/Route/City/Keelung" => [
        route_record(uid: "KEE0525", name: "306", headsign: "基隆車站—中平街(經西定路)"),
        route_record(uid: "KEE0531", name: "3062", headsign: "中平街—基隆車站(經西定路)"),
        route_record(uid: "KEE0532", name: "3063", headsign: "基隆車站—中平街(經西定路)—經成功市場")
      ],
      "v2/Bus/Shape/City/Keelung" => [
        shape_record(uid: "KEE0525"),
        shape_record(uid: "KEE0531", wkt: "LINESTRING(121.75 25.14, 121.76 25.15)"),
        shape_record(uid: "KEE0532", wkt: "LINESTRING(121.73 25.13, 121.74 25.14)")
      ],
      "v2/Bus/StopOfRoute/City/Keelung" => [
        stop_of_route_record(uid: "KEE0525"),
        stop_of_route_record(uid: "KEE0531", stop_uid: "KEE05311"),
        stop_of_route_record(uid: "KEE0532", stop_uid: "KEE05321")
      ]
    )

    result = Geojson::BusImporter.import!(
      city_id: "Keelung",
      client: client,
      rewrite_manifest: false
    )

    vias = result.routes.map do |slug|
      JSON.parse(Geojson::BusLayout.find_geojson(slug).read).dig("properties", "via")
    end
    assert_includes vias, "西定路"
    assert_includes vias, "西定路、成功市場"
    assert_equal 2, result.routes.length
  ensure
    result&.routes&.each { |slug| remove_keelung_fixture(slug) }
  end

  test "keeps extra-digit TDX names when no 3-digit parent exists" do
    client = FakeTdxClient.new(
      "v2/Bus/Route/City/Keelung" => [
        route_record(uid: "KEE0447", name: "4101", headsign: "七堵郵局—壯觀台北(經長庚醫院)")
      ],
      "v2/Bus/Shape/City/Keelung" => [ shape_record(uid: "KEE0447") ],
      "v2/Bus/StopOfRoute/City/Keelung" => [ stop_of_route_record(uid: "KEE0447") ]
    )

    result = Geojson::BusImporter.import!(
      city_id: "Keelung",
      client: client,
      rewrite_manifest: false
    )

    assert_equal [ "keelung_410" ], result.routes
    data = JSON.parse(Geojson::BusLayout.find_geojson("keelung_410").read)
    assert_equal "410", data.dig("properties", "ref")
    assert_nil data.dig("properties", "via")
  ensure
    result&.routes&.each { |slug| remove_keelung_fixture(slug) }
  end

  test "keeps Keelung 17xx routes in 1000+ instead of collapsing to 1xx" do
    client = FakeTdxClient.new(
      "v2/Bus/Route/City/Keelung" => [
        route_record(uid: "KEE1717", name: "1717", headsign: "基隆車站—大武崙")
      ],
      "v2/Bus/Shape/City/Keelung" => [ shape_record(uid: "KEE1717") ],
      "v2/Bus/StopOfRoute/City/Keelung" => [ stop_of_route_record(uid: "KEE1717") ]
    )

    result = Geojson::BusImporter.import!(
      city_id: "Keelung",
      client: client,
      rewrite_manifest: false
    )

    assert_equal [ "keelung_1717" ], result.routes
    path = Geojson::BusLayout.geojson_path(city_id: "Keelung", slug: "keelung_1717", ref: "1717")
    assert path.exist?
    assert_includes path.to_s, "/1000+/"
    data = JSON.parse(path.read)
    assert_equal "1717", data.dig("properties", "ref")
  ensure
    result&.routes&.each { |slug| remove_keelung_fixture(slug) }
  end

  test "omits via text when a route number has only one path" do
    client = FakeTdxClient.new(
      "v2/Bus/Route/City/Keelung" => [
        route_record(uid: "KEL992", name: "992", headsign: "信義國中—和平島(經祥豐街)")
      ],
      "v2/Bus/Shape/City/Keelung" => [ shape_record(uid: "KEL992") ],
      "v2/Bus/StopOfRoute/City/Keelung" => [ stop_of_route_record(uid: "KEL992") ]
    )

    result = Geojson::BusImporter.import!(
      city_id: "Keelung",
      client: client,
      rewrite_manifest: false
    )

    assert_equal [ "keelung_992" ], result.routes
    data = JSON.parse(Geojson::BusLayout.find_geojson("keelung_992").read)
    assert_equal "992", data.dig("properties", "name")
    assert_nil data.dig("properties", "via")
  ensure
    remove_keelung_fixture("keelung_992")
    result&.routes&.each { |slug| remove_keelung_fixture(slug) }
  end

  test "joins two via clauses with a dunhao instead of nested parentheses" do
    client = FakeTdxClient.new(
      "v2/Bus/Route/City/Keelung" => [
        route_record(uid: "KEL993A", name: "993", headsign: "八斗子—經美的世界(經八斗山莊)"),
        route_record(uid: "KEL993B", name: "993", headsign: "八斗子—經中正路")
      ],
      "v2/Bus/Shape/City/Keelung" => [
        shape_record(uid: "KEL993A"),
        shape_record(uid: "KEL993B")
      ],
      "v2/Bus/StopOfRoute/City/Keelung" => [
        stop_of_route_record(uid: "KEL993A"),
        stop_of_route_record(uid: "KEL993B")
      ]
    )

    result = Geojson::BusImporter.import!(
      city_id: "Keelung",
      client: client,
      rewrite_manifest: false
    )

    nested = result.routes.find { |slug| slug != "keelung_993_zhongzheng" }
    data = JSON.parse(Geojson::BusLayout.find_geojson(nested).read)
    assert_equal "美的世界、八斗山莊", data.dig("properties", "via")
    assert_equal "993（經美的世界、八斗山莊）", data.dig("properties", "name")
    refute_includes data.dig("properties", "name"), "(經"
  ensure
    result&.routes&.each { |slug| remove_keelung_fixture(slug) }
  end

  test "imports InterCity highway coaches from InterCity TDX paths" do
    client = FakeTdxClient.new(
      "v2/Bus/Route/InterCity" => [
        {
          "RouteUID" => "THB1820",
          "RouteName" => { "Zh_tw" => "1820", "En" => "1820" },
          "RouteMapImageUrl" => "https://web.taiwanbus.tw/MISUploadData/Schematic/file/1820.jpg",
          "Operators" => [
            {
              "OperatorID" => "45",
              "OperatorName" => { "Zh_tw" => "國光客運", "En" => "Kuo-Kuang Bus Co., Ltd." }
            }
          ],
          "SubRoutes" => [
            {
              "SubRouteUID" => "THB182001",
              "SubRouteName" => { "Zh_tw" => "1820" },
              "Direction" => 0,
              "Headsign" => "臺北→竹東"
            },
            {
              "SubRouteUID" => "THB182002",
              "SubRouteName" => { "Zh_tw" => "1820" },
              "Direction" => 1,
              "Headsign" => "竹東→臺北"
            },
            {
              "SubRouteUID" => "THB1820A1",
              "SubRouteName" => { "Zh_tw" => "1820A" },
              "Direction" => 0,
              "Headsign" => "臺北→竹東[繞駛關西市區]"
            },
            {
              "SubRouteUID" => "THB1820A2",
              "SubRouteName" => { "Zh_tw" => "1820A" },
              "Direction" => 1,
              "Headsign" => "竹東→臺北[繞駛關西市區]"
            }
          ]
        }
      ],
      "v2/Bus/Shape/InterCity" => [
        {
          "RouteUID" => "THB1820",
          "SubRouteUID" => "THB182001",
          "Direction" => 0,
          "Geometry" => "LINESTRING(121.5 25.0, 121.6 25.1)"
        },
        {
          "RouteUID" => "THB1820",
          "SubRouteUID" => "THB182002",
          "Direction" => 1,
          "Geometry" => "LINESTRING(121.6 25.1, 121.5 25.0)"
        },
        {
          "RouteUID" => "THB1820",
          "SubRouteUID" => "THB1820A1",
          "Direction" => 0,
          "Geometry" => "LINESTRING(121.5 25.0, 121.55 25.05, 121.6 25.1)"
        },
        {
          "RouteUID" => "THB1820",
          "SubRouteUID" => "THB1820A2",
          "Direction" => 1,
          "Geometry" => "LINESTRING(121.6 25.1, 121.55 25.05, 121.5 25.0)"
        }
      ],
      "v2/Bus/StopOfRoute/InterCity" => [
        {
          "RouteUID" => "THB1820",
          "SubRouteUID" => "THB182001",
          "Direction" => 0,
          "Stops" => [
            {
              "StopUID" => "THB1001",
              "StopName" => { "Zh_tw" => "台北轉運站", "En" => "Taipei Bus Station" },
              "StopSequence" => 1,
              "StopPosition" => { "PositionLon" => 121.5, "PositionLat" => 25.0 }
            }
          ]
        },
        {
          "RouteUID" => "THB1820",
          "SubRouteUID" => "THB1820A1",
          "Direction" => 0,
          "Stops" => [
            {
              "StopUID" => "THB1001",
              "StopName" => { "Zh_tw" => "台北轉運站", "En" => "Taipei Bus Station" },
              "StopSequence" => 1,
              "StopPosition" => { "PositionLon" => 121.5, "PositionLat" => 25.0 }
            }
          ]
        }
      ]
    )

    result = Geojson::BusImporter.import!(
      city_id: "InterCity",
      client: client,
      rewrite_manifest: false
    )

    path = Geojson::BusLayout.geojson_path(
      city_id: "InterCity",
      slug: "inter_city_1820",
      ref: "1820",
      operator_id: "45",
      operator_name: "國光客運"
    )
    path_a = Geojson::BusLayout.geojson_path(
      city_id: "InterCity",
      slug: "inter_city_1820a",
      ref: "1820A",
      operator_id: "45",
      operator_name: "國光客運"
    )
    assert_equal [ "inter_city_1820", "inter_city_1820a" ].sort, result.routes.sort
    assert path.exist?
    assert path_a.exist?

    data = JSON.parse(path.read)
    assert_equal "InterCity", data.dig("properties", "city_id")
    assert_equal "1820", data.dig("properties", "ref")
    assert_equal "45", data.dig("properties", "operator_id")
    assert_equal "國光客運", data.dig("properties", "operator")
    assert_equal data.dig("properties", "color"), JSON.parse(path_a.read).dig("properties", "color")
    assert_includes data.dig("properties", "official_map_url"), "1820.jpg"

    data_a = JSON.parse(path_a.read)
    assert_equal "1820A", data_a.dig("properties", "ref")
    assert_includes data_a.dig("properties", "name"), "繞駛關西市區"
  ensure
    %w[inter_city_1820 inter_city_1820a].each do |slug|
      leftover = Geojson::BusLayout.find_geojson(slug)
      FileUtils.rm_f(leftover) if leftover
    end
  end

  test "exposes InterCity and city TDX paths" do
    city = Geojson::BusCatalog.find("Keelung")
    intercity = Geojson::BusCatalog.find("InterCity")

    assert_equal "v2/Bus/Route/City/Keelung", Geojson::BusImporter.route_path_for(city)
    assert_equal "v2/Bus/Shape/City/Keelung", Geojson::BusImporter.shape_path_for(city)
    assert_equal "v2/Bus/StopOfRoute/City/Keelung", Geojson::BusImporter.stop_of_route_path_for(city)
    assert_equal "v2/Bus/Route/InterCity", Geojson::BusImporter.route_path_for(intercity)
    assert_equal "v2/Bus/Shape/InterCity", Geojson::BusImporter.shape_path_for(intercity)
    assert_equal "v2/Bus/StopOfRoute/InterCity", Geojson::BusImporter.stop_of_route_path_for(intercity)
  end

  test "skips TDX test routes when grouping city routes" do
    city = Geojson::BusCatalog.find("Kaohsiung")
    routes = [
      route_record(uid: "KHH1", name: "紅1"),
      route_record(uid: "KHHTEST", name: "測試路線"),
      route_record(uid: "KHHTEST2", name: "測試路線2")
    ]

    slugs = Geojson::BusImporter.grouped_routes(routes, city:).map(&:first)

    assert_includes slugs, "kaohsiung_hong1"
    assert_not_includes slugs, "kaohsiung_95c1ce5b71"
    assert(slugs.none? { |slug| slug.include?("測試") || slug.match?(/95c1ce5b71|87ee037057/) })
  end

  private

  def remove_keelung_fixture(*slugs)
    slugs.flatten.compact.each do |slug|
      path = Geojson::BusLayout.find_geojson(slug)
      FileUtils.rm_f(path) if path&.exist?
    end
  end

  def route_record(uid: "KEL901", name: "901", map_url: nil, headsign: nil)
    record = {
      "RouteUID" => uid,
      "RouteName" => { "Zh_tw" => name, "En" => name },
      "RouteMapImageUrl" => map_url,
      "Operators" => [
        {
          "OperatorID" => "KeelungBus",
          "OperatorName" => { "Zh_tw" => "基隆市公車處", "En" => "Keelung City Bus" }
        }
      ]
    }
    if headsign
      record["SubRoutes"] = [
        { "SubRouteUID" => "#{uid}01", "SubRouteName" => { "Zh_tw" => name }, "Direction" => 0, "Headsign" => headsign }
      ]
    end
    record
  end

  def shape_record(uid: "KEL901", direction: 0, wkt: "LINESTRING(121.739 25.132, 121.744 25.128)")
    {
      "RouteUID" => uid,
      "Direction" => direction,
      "Geometry" => wkt
    }
  end

  test "keeps full inbound geometry even when it overlaps outbound corridor" do
    shared = "LINESTRING(121.7400 25.1300, 121.7410 25.1300, 121.7420 25.1300, 121.7430 25.1300)"
    inbound_spur = "LINESTRING(121.7400 25.1300, 121.7410 25.1300, 121.7420 25.1300, 121.7420 25.1310, 121.7420 25.1320)"

    client = FakeTdxClient.new(
      "v2/Bus/Route/City/Keelung" => [ route_record ],
      "v2/Bus/Shape/City/Keelung" => [
        shape_record(direction: 0, wkt: shared),
        shape_record(direction: 1, wkt: inbound_spur)
      ],
      "v2/Bus/StopOfRoute/City/Keelung" => [ stop_of_route_record ]
    )

    Geojson::BusImporter.import!(
      city_id: "Keelung",
      series: "9",
      client: client,
      rewrite_manifest: false
    )

    data = JSON.parse(Geojson::BusLayout.geojson_path(city_id: "Keelung", slug: "keelung_901", ref: "901").read)
    routes = data["features"].select { |feature| feature.dig("properties", "feature_type") == "route" }
    outbound = routes.select { |feature| feature.dig("properties", "direction").to_i.zero? }
    inbound = routes.select { |feature| feature.dig("properties", "direction").to_i == 1 }

    assert_operator outbound.sum { |feature| feature.dig("geometry", "coordinates").length }, :>=, 4
    # Must retain the full return path (shared corridor + spur), not spur stubs only.
    assert_operator inbound.sum { |feature| feature.dig("geometry", "coordinates").length }, :>=, 5
  ensure
    remove_keelung_fixture("keelung_901")
  end

  def stop_of_route_record(uid: "KEL901", stop_uid: "KEL1001", stop_name: "基隆車站", station_id: "KELST01")
    {
      "RouteUID" => uid,
      "Stops" => [
        {
          "StopUID" => stop_uid,
          "StationID" => station_id,
          "StopName" => { "Zh_tw" => stop_name, "En" => "Keelung Station" },
          "StopSequence" => 1,
          "StopPosition" => { "PositionLon" => 121.7394, "PositionLat" => 25.1318 }
        }
      ]
    }
  end
end
