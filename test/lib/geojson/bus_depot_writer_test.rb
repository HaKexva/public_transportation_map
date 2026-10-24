# frozen_string_literal: true

require "test_helper"

class GeojsonBusDepotWriterTest < ActiveSupport::TestCase
  setup do
    @root = Rails.root.join("tmp/bus_depot_writer_test_#{SecureRandom.hex(4)}")
    @city_dir = @root.join("keelung_bus")
    @out = @root.join("bus_depots.json")
    @manual = @root.join("none.csv")
    FileUtils.mkdir_p(@city_dir)
  end

  teardown do
    FileUtils.rm_rf(@root)
  end

  test "aggregates dispatch yards across routes and skips market parking noise" do
    write_route!(
      "keelung_602",
      name: "602",
      stations: [
        {
          "feature_type" => "station",
          "ref" => "KELDEPOT",
          "station_id" => "DEPOT1",
          "name" => "暖暖分站(調度站)",
          "stop_role" => "depot",
          "coordinates" => [ 121.74, 25.10 ]
        },
        {
          "feature_type" => "station",
          "ref" => "KELMKT",
          "name" => "立體停車場(五股公有市場)",
          "coordinates" => [ 121.45, 25.08 ]
        },
        {
          "feature_type" => "station",
          "ref" => "NANGANG",
          "station_id" => "MRTDEPOT",
          "name" => "南港機廠",
          "stop_role" => "depot",
          "coordinates" => [ 121.60, 25.05 ]
        }
      ]
    )
    write_route!(
      "keelung_603",
      name: "603",
      stations: [
        {
          "feature_type" => "station",
          "ref" => "KELDEPOT2",
          "station_id" => "DEPOT1",
          "name" => "暖暖分站(調度站)",
          "coordinates" => [ 121.7401, 25.1001 ]
        },
        {
          "feature_type" => "station",
          "ref" => "ZHONG",
          "name" => "中壢總站",
          "coordinates" => [ 121.22, 24.95 ]
        }
      ]
    )

    result = Geojson::BusDepotWriter.write!(path: @out, bus_root: @root, manual_path: @manual)
    names = result.depots.map { |depot| depot["name"] }
    assert_includes names, "暖暖分站(調度站)"
    assert_includes names, "中壢總站"
    refute_includes names, "南港機廠"
    refute_includes names, "立體停車場(五股公有市場)"

    depot = result.depots.find { |entry| entry["name"] == "暖暖分站(調度站)" }
    assert_equal %w[keelung_602 keelung_603], depot["routes"]
    assert_in_delta 121.74, depot["lon"], 0.001
    assert_in_delta 25.10, depot["lat"], 0.001
  end

  test "lists routes without a depot and merges filled manual rows" do
    manual = @root.join("manual.md")
    write_route!(
      "keelung_101",
      name: "101",
      stations: [
        { "feature_type" => "station", "direction" => 0, "name" => "起點", "coordinates" => [ 121.70, 25.10 ] },
        { "feature_type" => "station", "direction" => 0, "name" => "終點", "coordinates" => [ 121.72, 25.12 ] }
      ]
    )
    write_route!(
      "keelung_102",
      name: "102",
      stations: [ { "feature_type" => "station", "direction" => 0, "name" => "某站", "coordinates" => [ 121.73, 25.13 ] } ]
    )

    stations = @root.join(Geojson::BusDepotWriter::STATIONS_BASENAME)

    assert_equal 2, Geojson::BusDepotWriter.write_missing!(path: @out, bus_root: @root, manual_path: manual)
    markdown = File.read(manual)
    assert_includes markdown, "## 基隆市 `keelung_bus`（2 條路線，已指定 0）"
    assert_includes markdown, "| 101 |  | 起點 | 終點 |  | keelung_101 |"
    refute_includes markdown, "### 場站清單"

    depot_rows = [ { "city" => "keelung_bus", "code" => "N1", "name" => "八堵調度站", "lon" => "121.70", "lat" => "25.10" } ]
    File.write(stations, Geojson::BusDepotWriter.manual_markdown(depot_rows:, intro: Geojson::BusDepotWriter::STATIONS_INTRO))
    File.write(manual, markdown.sub("| 101 |  | 起點 | 終點 |  |", "| 101 |  | 起點 | 終點 | N1 |"))

    assert_equal 1, Geojson::BusDepotWriter.write_missing!(path: @out, bus_root: @root, manual_path: manual)
    depots = JSON.parse(File.read(@out))
    assert_equal [ [ "八堵調度站", [ "keelung_101" ], 121.70, 25.10 ] ], depots.map { |depot| depot.values_at("name", "routes", "lon", "lat") }
    markdown = File.read(manual)
    assert_includes markdown, "（2 條路線，已指定 1）"
    assert_includes markdown, "| 101 |  | 起點 | 終點 | N1 | keelung_101 |"
    station_markdown = File.read(stations)
    assert_includes station_markdown, "## 基隆市 `keelung_bus`（1 個場站）"
    assert_includes station_markdown, "| N1 | 八堵調度站 | 121.70 | 25.10 |  |"
    refute_includes station_markdown, "### 路線"
  end

  test "lists auto-detected depots and assigns routes to them by code" do
    manual = @root.join("manual.md")
    write_route!(
      "keelung_602",
      name: "602",
      stations: [ { "feature_type" => "station", "station_id" => "DEPOT1", "name" => "暖暖分站(調度站)", "coordinates" => [ 121.74, 25.10 ] } ]
    )
    write_route!(
      "keelung_605",
      name: "605",
      stations: [ { "feature_type" => "station", "direction" => 0, "name" => "某站", "coordinates" => [ 121.73, 25.13 ] } ]
    )

    stations = @root.join(Geojson::BusDepotWriter::STATIONS_BASENAME)

    assert_equal 1, Geojson::BusDepotWriter.write_missing!(path: @out, bus_root: @root, manual_path: manual)
    assert_match(/\| SDEPOT1 \| 暖暖分站\(調度站\) \| 121\.74 \| 25\.1 \| 自動偵測・1 條路線・\[地圖\]/, File.read(stations))

    File.write(manual, File.read(manual).sub("| 605 |  | 某站 | 某站 |  |", "| 605 |  | 某站 | 某站 | SDEPOT1 |"))

    assert_equal 0, Geojson::BusDepotWriter.write_missing!(path: @out, bus_root: @root, manual_path: manual)
    depots = JSON.parse(File.read(@out))
    assert_equal [ [ "暖暖分站(調度站)", %w[keelung_602 keelung_605] ] ], depots.map { |depot| depot.values_at("name", "routes") }
    assert_includes File.read(stations), "自動偵測・2 條路線"
  end

  test "hand assignment overrides an auto-detected depot" do
    manual = @root.join("manual.md")
    write_route!(
      "keelung_602",
      name: "602",
      stations: [ { "feature_type" => "station", "station_id" => "DEPOT1", "name" => "暖暖分站(調度站)", "coordinates" => [ 121.74, 25.10 ] } ]
    )
    route_rows = [ { "city" => "keelung_bus", "route_id" => "keelung_602", "route_name" => "602", "depot_code" => "N1" } ]
    depot_rows = [ { "city" => "keelung_bus", "code" => "N1", "name" => "八堵調度站", "lon" => "121.70", "lat" => "25.10" } ]
    File.write(manual, Geojson::BusDepotWriter.manual_markdown(depot_rows:, route_rows:))

    result = Geojson::BusDepotWriter.write!(path: @out, bus_root: @root, manual_path: manual)
    assert_equal [ [ "八堵調度站", [ "keelung_602" ] ] ], result.depots.map { |depot| depot.values_at("name", "routes") }
  end

  test "swaps hand-entered coordinates pasted in latitude, longitude order" do
    manual = @root.join("manual.md")
    write_route!("keelung_602", name: "602", stations: [ { "feature_type" => "station", "direction" => 0, "name" => "某站", "coordinates" => [ 121.73, 25.13 ] } ])
    route_rows = [ { "city" => "keelung_bus", "route_id" => "keelung_602", "route_name" => "602", "depot_code" => "N1" } ]
    depot_rows = [ { "city" => "keelung_bus", "code" => "N1", "name" => "八堵調度站", "lon" => "25.10", "lat" => "121.70" } ]
    File.write(manual, Geojson::BusDepotWriter.manual_markdown(depot_rows:, route_rows:))

    result = Geojson::BusDepotWriter.write!(path: @out, bus_root: @root, manual_path: manual)
    assert_equal [ [ 121.70, 25.10 ] ], result.depots.map { |depot| depot.values_at("lon", "lat") }
  end

  test "converts full and short Plus Codes pasted into the coordinate cells" do
    manual = @root.join("manual.md")
    stations = @root.join(Geojson::BusDepotWriter::STATIONS_BASENAME)
    write_route!("keelung_603", name: "603", stations: [ { "feature_type" => "station", "direction" => 0, "name" => "某站", "coordinates" => [ 121.73, 25.13 ] } ])
    File.write(manual, Geojson::BusDepotWriter.manual_markdown(route_rows: [
      { "city" => "keelung_bus", "route_id" => "keelung_603", "route_name" => "603", "depot_code" => "N1, N2" }
    ]))
    File.write(stations, Geojson::BusDepotWriter.manual_markdown(depot_rows: [
      { "city" => "keelung_bus", "code" => "N1", "name" => "全碼場站", "lon" => "7QQ32GX8+4R", "lat" => "" },
      { "city" => "keelung_bus", "code" => "N2", "name" => "短碼場站", "lon" => "2GX8+4R 臺北市", "lat" => "" }
    ], intro: Geojson::BusDepotWriter::STATIONS_INTRO))

    assert_equal 2, Geojson::BusDepotWriter.refresh_stations!(manual_path: manual)
    rows = Geojson::BusDepotWriter.parse_manual(stations).depots.index_by { |row| row["code"] }
    assert_equal [ "121.517063", "25.047813" ], rows["N1"].values_at("lon", "lat")
    assert_equal [ "121.517063", "25.047813" ], rows["N2"].values_at("lon", "lat")
    assert_equal "Plus Code 2GX8+4R", rows["N2"]["note"]
  end

  test "groups the stations file by operator with hand codes first" do
    markdown = Geojson::BusDepotWriter.manual_markdown(depot_rows: [
      { "city" => "taipei_new_taipei_bus", "code" => "S5", "name" => "首都客運某站" },
      { "city" => "taipei_new_taipei_bus", "code" => "N10", "name" => "首都客運內湖站" },
      { "city" => "taipei_new_taipei_bus", "code" => "N2", "name" => "台北客運中和站" },
      { "city" => "taipei_new_taipei_bus", "code" => "N9", "name" => "首都客運三重站" },
      { "city" => "taipei_new_taipei_bus", "code" => "S7", "name" => "板橋客運站" }
    ], intro: "")

    assert_equal [ "臺北客運（1 個）", "首都客運（3 個）", "其他（1 個）" ], markdown.scan(/^### (.+)$/).flatten
    assert_operator markdown.index("| N9 |"), :<, markdown.index("| N10 |")
    assert_operator markdown.index("| N10 |"), :<, markdown.index("| S5 |")
  end

  test "assigns routes to a hand-added depot without coordinates" do
    manual = @root.join("manual.md")
    write_route!(
      "keelung_602",
      name: "602",
      stations: [ { "feature_type" => "station", "station_id" => "DEPOT1", "name" => "暖暖分站(調度站)", "coordinates" => [ 121.74, 25.10 ] } ]
    )
    route_rows = [ { "city" => "keelung_bus", "route_id" => "keelung_602", "route_name" => "602", "depot_code" => "N1" } ]
    depot_rows = [ { "city" => "keelung_bus", "code" => "N1", "name" => "八堵調度站", "note" => "基隆市七堵區某路1號" } ]
    File.write(manual, Geojson::BusDepotWriter.manual_markdown(depot_rows:, route_rows:))

    result = Geojson::BusDepotWriter.write!(path: @out, bus_root: @root, manual_path: manual)
    assert_equal 1, result.depots.length
    depot = result.depots.first
    assert_equal [ "八堵調度站", [ "keelung_602" ], "基隆市七堵區某路1號" ], depot.values_at("name", "routes", "address")
    assert_nil depot["lon"]
    assert_nil depot["lat"]
  end

  test "assigns a jointly operated route to every listed depot" do
    manual = @root.join("manual.md")
    write_route!(
      "keelung_102",
      name: "102",
      stations: [ { "feature_type" => "station", "direction" => 0, "name" => "某站", "coordinates" => [ 121.73, 25.13 ] } ]
    )
    route_rows = [ { "city" => "keelung_bus", "route_id" => "keelung_102", "route_name" => "102", "depot_code" => "N1, N2、N9" } ]
    depot_rows = [
      { "city" => "keelung_bus", "code" => "N1", "name" => "甲站", "lon" => "121.70", "lat" => "25.10" },
      { "city" => "keelung_bus", "code" => "N2", "name" => "乙站", "note" => "基隆市某路1號" }
    ]
    File.write(manual, Geojson::BusDepotWriter.manual_markdown(depot_rows:, route_rows:))

    result = nil
    assert_output(nil, /Depot N9 for keelung_102 is not in any depot list/) do
      result = Geojson::BusDepotWriter.write!(path: @out, bus_root: @root, manual_path: manual)
    end
    assert_equal [ [ "乙站", [ "keelung_102" ] ], [ "甲站", [ "keelung_102" ] ] ], result.depots.map { |depot| depot.values_at("name", "routes") }
  end

  test "keeps routes marked # as deferred without assigning them" do
    manual = @root.join("manual.md")
    write_route!(
      "keelung_102",
      name: "102",
      stations: [ { "feature_type" => "station", "direction" => 0, "name" => "某站", "coordinates" => [ 121.73, 25.13 ] } ]
    )
    route_rows = [ { "city" => "keelung_bus", "route_id" => "keelung_102", "route_name" => "102", "depot_code" => "#" } ]
    File.write(manual, Geojson::BusDepotWriter.manual_markdown(depot_rows: [], route_rows:))

    assert_output(/0 routes without a depot/, "") do
      assert_equal 0, Geojson::BusDepotWriter.write_missing!(path: @out, bus_root: @root, manual_path: manual)
    end
    assert_empty JSON.parse(File.read(@out))
    markdown = File.read(manual)
    assert_includes markdown, "（1 條路線，已指定 0，暫緩 1）"
    assert_includes markdown, "<details><summary>暫緩（1 條）</summary>\n\n| 路線 |"
    assert_includes markdown, "| 102 |  |  |  | # | keelung_102 |\n\n</details>"
  end

  test "confirm moves assigned routes into the confirmed file and depots into the stations file" do
    manual = @root.join("manual.md")
    confirmed = @root.join(Geojson::BusDepotWriter::CONFIRMED_BASENAME)
    stations = @root.join(Geojson::BusDepotWriter::STATIONS_BASENAME)
    write_route!("keelung_101", name: "101", stations: [ { "feature_type" => "station", "direction" => 0, "name" => "甲", "coordinates" => [ 121.70, 25.10 ] } ])
    write_route!("keelung_102", name: "102", stations: [ { "feature_type" => "station", "direction" => 0, "name" => "乙", "coordinates" => [ 121.73, 25.13 ] } ])
    route_rows = [
      { "city" => "keelung_bus", "route_id" => "keelung_101", "route_name" => "101", "depot_code" => "N1" },
      { "city" => "keelung_bus", "route_id" => "keelung_102", "route_name" => "102", "depot_code" => "#" }
    ]
    depot_rows = [
      { "city" => "keelung_bus", "code" => "N1", "name" => "八堵調度站", "note" => "基隆市某路1號" },
      { "city" => "keelung_bus", "code" => "N2", "name" => "未用站" }
    ]
    File.write(manual, Geojson::BusDepotWriter.manual_markdown(depot_rows:, route_rows:))

    assert_equal 1, Geojson::BusDepotWriter.confirm!(manual_path: manual).routes

    kept = Geojson::BusDepotWriter.parse_manual(manual)
    assert_equal [ "keelung_102" ], kept.routes.map { |row| row["route_id"] }
    assert_empty kept.depots
    moved = Geojson::BusDepotWriter.parse_manual(confirmed)
    assert_equal [ [ "keelung_101", "N1" ] ], moved.routes.map { |row| row.values_at("route_id", "depot_code") }
    assert_empty moved.depots
    assert_equal [ [ "N1", "基隆市某路1號" ], [ "N2", "" ] ],
      Geojson::BusDepotWriter.parse_manual(stations).depots.map { |row| row.values_at("code", "note") }

    assert_equal 0, Geojson::BusDepotWriter.write_missing!(path: @out, bus_root: @root, manual_path: manual)
    depots = JSON.parse(File.read(@out))
    assert_equal [ [ "八堵調度站", [ "keelung_101" ], "基隆市某路1號" ] ], depots.map { |depot| depot.values_at("name", "routes", "address") }
    assert_equal [ "keelung_102" ], Geojson::BusDepotWriter.parse_manual(manual).routes.map { |row| row["route_id"] }
    assert_equal %w[N1 N2], Geojson::BusDepotWriter.parse_manual(stations).depots.map { |row| row["code"] }
  end

  test "escapes pipes in manual table cells" do
    route_rows = [ { "city" => "keelung_bus", "route_id" => "k1", "route_name" => "A|B", "depot_code" => "N1" } ]
    depot_rows = [ { "city" => "keelung_bus", "code" => "N1", "name" => "站|場", "lon" => "121.7", "lat" => "25.1" } ]
    manual = @root.join("pipes.md")
    File.write(manual, Geojson::BusDepotWriter.manual_markdown(depot_rows:, route_rows:))

    parsed = Geojson::BusDepotWriter.parse_manual(manual)
    assert_equal [ [ "keelung_bus", "k1", "A|B", "N1" ] ], parsed.routes.map { |row| row.values_at("city", "route_id", "route_name", "depot_code") }
    assert_equal [ [ "N1", "站|場", "121.7" ] ], parsed.depots.map { |row| row.values_at("code", "name", "lon") }
  end

  private

  def write_route!(slug, name:, stations:)
    features = stations.map { |station|
      {
        "type" => "Feature",
        "properties" => station.except("coordinates"),
        "geometry" => { "type" => "Point", "coordinates" => station["coordinates"] }
      }
    }
    payload = {
      "type" => "FeatureCollection",
      "properties" => {
        "id" => slug,
        "city_id" => "Keelung",
        "ref" => name,
        "name" => name,
        "color" => "#0B7A3E"
      },
      "features" => features
    }
    File.write(@city_dir.join("#{slug}.geojson"), "#{JSON.pretty_generate(payload)}\n")
  end
end
