# frozen_string_literal: true

require "test_helper"

class Transit::ItineraryRouterTest < ActiveSupport::TestCase
  MONDAY = Time.zone.local(2026, 10, 26, 7, 40, 0)
  SUNDAY = Time.zone.local(2026, 10, 25, 8, 0, 0)

  test "rides a timetable after walking to the stop" do
    origin = { "name" => "出發", "lat" => 25.05 - (300.0 / 111_320), "lon" => 121.50 }
    graph = graph_with([
      route("local", "區間車", "rail", [
        stop("a", "甲站", 25.05, 121.50),
        stop("b", "乙站", 25.08, 121.50)
      ], "weekday" => { trips: [ [ 8 * 60, 8 * 60 + 20 ] ] })
    ])
    itinerary = search(graph, origin, point(25.08, 121.50, "乙站"), MONDAY).first

    assert_equal "earliest", itinerary["profile"]
    ride = itinerary["legs"].find { |leg| leg["kind"] == "ride" }
    assert_equal "台鐵", ride["name"]
    assert_equal "區間車", ride["line_name"]
    assert_equal (8 * 60 + 20) - (7 * 60 + 40), itinerary["duration_minutes"]
    assert itinerary["walk_minutes"].positive?
  end

  test "aligns a headway boarding to the next departure" do
    graph = graph_with([
      route("blue", "藍線", "metro", [
        stop("a", "甲", 25.0, 121.5),
        stop("b", "乙", 25.03, 121.5)
      ], "weekday" => { headways: [ { start: 6 * 60, end: 23 * 60, every: 6, ride: [ 4 ] } ] })
    ])
    depart = Time.zone.local(2026, 10, 26, 8, 2, 0)
    itinerary = search(graph, point(25.0, 121.5, "甲"), point(25.03, 121.5, "乙"), depart).first

    ride = itinerary["legs"].find { |leg| leg["kind"] == "ride" }
    assert_equal "08:06", Time.zone.parse(ride["board_at"]).strftime("%H:%M")
    assert_equal "08:10", Time.zone.parse(ride["alight_at"]).strftime("%H:%M")
    assert_equal 8, itinerary["duration_minutes"]
  end

  test "returns nothing when the only service does not run that day" do
    graph = graph_with([
      route("local", "區間車", "rail", [
        stop("a", "甲", 25.0, 121.5),
        stop("b", "乙", 25.05, 121.5)
      ], "weekday" => { trips: [ [ 8 * 60, 8 * 60 + 20 ] ] })
    ])
    assert_empty search(graph, point(25.0, 121.5, "甲"), point(25.05, 121.5, "乙"), SUNDAY)
  end

  test "offers an earlier transfer and a direct ride with fewer transfers" do
    graph = graph_with([
      route("direct", "直達公車", "bus", [
        stop("x", "起站", 25.0, 121.5),
        stop("z", "迄站", 25.02, 121.5)
      ], "weekday" => { trips: [ [ 8 * 60 + 10, 9 * 60 ] ] }),
      route("feeder", "接駁", "bus", [
        stop("x", "起站", 25.0, 121.5),
        stop("ybus", "轉乘", 25.01, 121.5)
      ], "weekday" => { trips: [ [ 8 * 60 + 5, 8 * 60 + 15 ] ] }),
      route("metro", "捷運", "metro", [
        stop("ymetro", "轉乘", 25.01, 121.5),
        stop("z", "迄站", 25.02, 121.5)
      ], "weekday" => { headways: [ { start: 6 * 60, end: 23 * 60, every: 5, ride: [ 10 ] } ] })
    ])
    results = search(graph, point(25.0, 121.5, "起站"), point(25.02, 121.5, "迄站"), Time.zone.local(2026, 10, 26, 8, 0, 0))
    earliest = results.find { |item| item["profile"] == "earliest" }
    fewer = results.find { |item| item["profile"] == "fewer_transfers" }

    assert_equal %w[接駁 捷運], earliest["legs"].select { |leg| leg["kind"] == "ride" }.map { |leg| leg["name"] }
    assert_equal [ "直達公車" ], fewer["legs"].select { |leg| leg["kind"] == "ride" }.map { |leg| leg["name"] }
    assert earliest["duration_minutes"] < fewer["duration_minutes"]
  end

  test "lists each rail train and its times on the ride" do
    graph = graph_with([
      route("local", "區間車", "rail", [
        stop("a", "甲站", 25.0, 121.5),
        stop("b", "乙站", 25.02, 121.5)
      ], "weekday" => { trips: [
        { train: "133", times: [ 8 * 60, 8 * 60 + 20 ] },
        { train: "135", times: [ 9 * 60, 9 * 60 + 20 ] }
      ] })
    ])
    ride = search(graph, point(25.0, 121.5, "甲站"), point(25.02, 121.5, "乙站"), Time.zone.local(2026, 10, 26, 7, 50, 0))
      .first["legs"].find { |leg| leg["kind"] == "ride" }

    assert_equal "133", ride["train_number"]
    assert_equal [ "甲站", "乙站" ], ride["stops"].map { |stop| stop["name"] }
    assert_equal %w[133 135], ride["departures"].map { |row| row["train_number"] }
    assert ride["departures"].first["chosen"]
  end

  test "lists headway departures so the rider can pick another trip" do
    graph = graph_with([
      route("blue", "藍線", "metro", [
        stop("a", "甲", 25.0, 121.5),
        stop("b", "乙", 25.03, 121.5)
      ], "weekday" => { headways: [ { start: 8 * 60, end: 9 * 60, every: 10, ride: [ 4 ] } ] })
    ])
    ride = search(graph, point(25.0, 121.5, "甲"), point(25.03, 121.5, "乙"), Time.zone.local(2026, 10, 26, 8, 0, 0))
      .first["legs"].find { |leg| leg["kind"] == "ride" }

    assert_operator ride["departures"].length, :>=, 2
    assert_equal "08:00", Time.zone.parse(ride["departures"].first["board_at"]).strftime("%H:%M")
    assert ride["departures"].first["chosen"]
    assert_equal "08:10", Time.zone.parse(ride["departures"].second["board_at"]).strftime("%H:%M")
  end

  test "offers another route after hiding the first itinerary's lines" do
    graph = graph_with([
      route("fast", "快線", "bus", [
        stop("x", "起站", 25.0, 121.5),
        stop("z", "迄站", 25.03, 121.5)
      ], "weekday" => { trips: [ [ 8 * 60, 8 * 60 + 20 ] ] }),
      route("slow", "慢線", "bus", [
        stop("x", "起站", 25.0, 121.5),
        stop("z", "迄站", 25.03, 121.5)
      ], "weekday" => { trips: [ [ 8 * 60 + 5, 8 * 60 + 40 ] ] })
    ])
    results = search(graph, point(25.0, 121.5, "起站"), point(25.03, 121.5, "迄站"), Time.zone.local(2026, 10, 26, 7, 50, 0))
    names = results.map { |item| item["legs"].find { |leg| leg["kind"] == "ride" }["name"] }

    assert_includes names, "快線"
    assert_includes names, "慢線"
    assert results.any? { |item| item["profile"] == "alternate" }
  end

  test "collapses consecutive TRA line hops into one 台鐵 leg with full geometry" do
    graph = graph_with([
      route("tra:western_trunk_south:forward", "縱貫線（南段）", "rail", [
        stop("a", "臺南", 23.0, 120.2),
        stop("b", "嘉義", 23.5, 120.4)
      ], "weekday" => { trips: [ { train: "122", times: [ 8 * 60, 8 * 60 + 40 ] } ] }),
      route("tra:coastal_east:forward", "臺東線", "rail", [
        stop("b2", "嘉義", 23.5, 120.4),
        stop("c", "花蓮", 24.0, 121.6)
      ], "weekday" => { trips: [ { train: "122", times: [ 8 * 60 + 45, 8 * 60 + 180 ] } ] })
    ])
    # Force a transfer walk between the two rail patterns via nearby stops.
    # Same-name hubs within transfer distance get a footpath from the compiler.
    itinerary = search(
      graph,
      point(23.0, 120.2, "臺南"),
      point(24.0, 121.6, "花蓮"),
      Time.zone.local(2026, 10, 26, 7, 50, 0)
    ).first

    rides = itinerary["legs"].select { |leg| leg["kind"] == "ride" }
    assert_equal 1, rides.length, rides.map { |leg| leg["name"] }.inspect
    assert_equal "台鐵", rides.first["name"]
    assert_operator rides.first["geometry"].length, :>=, 2
    refute_includes rides.map { |leg| leg["name"] }, "縱貫線（南段）"
    refute_includes rides.map { |leg| leg["name"] }, "臺東線"
  end

  test "still offers highway coach when HSR is the fastest trunk" do
    # Far enough that RAPTOR treats the coach as a long-haul trunk (>90 min).
    south = 25.0 - (280_000.0 / 111_320)
    graph = graph_with([
      route("hsr", "台灣高鐵", "hsr", [
        stop("n", "台北", 25.0, 121.5),
        stop("s", "左營", south, 121.5)
      ], "weekday" => { trips: [ [ 8 * 60, 8 * 60 + 100 ] ] }),
      {
        id: "inter_city_999",
        name: "國道客運",
        mode: "bus",
        stops: [
          stop("n", "台北", 25.0, 121.5),
          stop("s", "高雄", south, 121.5)
        ],
        services: { "weekday" => { trips: [ [ 8 * 60, 8 * 60 + 280 ] ] } }
      }
    ])
    results = search(graph, point(25.0, 121.5, "台北"), point(south, 121.5, "高雄"), Time.zone.local(2026, 10, 26, 7, 40, 0))
    modes = results.flat_map { |item| item["legs"].select { |leg| leg["kind"] == "ride" }.map { |leg| leg["mode"] } }.uniq
    names = results.flat_map { |item| item["legs"].select { |leg| leg["kind"] == "ride" }.map { |leg| leg["name"] } }

    assert_includes modes, "hsr"
    assert_includes modes, "bus"
    assert_includes names, "國道客運"
    assert results.any? { |item| item["profile"] == "coach" }
  end

  test "offers a later trip when nothing runs in the first three hours" do
    graph = graph_with([
      route("local", "區間車", "rail", [
        stop("a", "甲站", 25.0, 121.5),
        stop("b", "乙站", 25.05, 121.5)
      ], "weekday" => { trips: [ { train: "201", times: [ 14 * 60, 14 * 60 + 25 ] } ] })
    ])
    router = Transit::Itinerary::Router.new(
      graph,
      origin: point(25.0, 121.5, "甲站"),
      destination: point(25.05, 121.5, "乙站"),
      depart_at: Time.zone.local(2026, 10, 26, 8, 0, 0)
    )
    itinerary = router.call.first

    assert_equal "這段時間沒有班車，以下是當天較晚的替代路線。", router.notice
    assert itinerary["later"]
    assert_equal "201", itinerary["legs"].find { |leg| leg["kind"] == "ride" }["train_number"]
  end

  test "walks when the two points are close and no transit fits" do
    graph = Transit::Itinerary::Graph.empty
    origin = point(25.0, 121.5, "甲")
    destination = point(25.0 + (400.0 / 111_320), 121.5, "乙")
    itinerary = Transit::Itinerary::Router.new(graph, origin:, destination:, depart_at: MONDAY).call.first

    assert_equal "walk", itinerary["profile"]
    assert_equal "步行", itinerary["legs"].first["name"]
  end

  test "plans island trips with ferry outside the O-D box and a flight alternate" do
    graph = graph_with([
      route("rail", "縱貫線", "rail", [
        stop("tpe", "台北", 25.05, 121.52, "rail"),
        stop("khh", "高雄", 22.64, 120.30, "rail")
      ], "weekday" => { trips: [ [ 8 * 60, 12 * 60 ] ] }),
      route("ferry", "高雄－馬公渡輪", "ferry", [
        stop("pier", "新濱碼頭", 22.6405, 120.3005, "ferry"),
        stop("magong_pier", "馬公商港", 23.5636, 119.5641, "ferry")
      ], "daily" => { trips: [ [ 13 * 60, 18 * 60 ] ] }),
      route("flight", "松山－馬公", "flight", [
        stop("tsa", "台北松山機場", 25.0505, 121.5205, "flight"),
        stop("mzg", "澎湖馬公機場", 23.5640, 119.5650, "flight")
      ], "daily" => { trips: [ [ 9 * 60, 10 * 60 ] ] })
    ])

    results = search(
      graph,
      point(25.05, 121.52, "台北車站"),
      point(23.5636, 119.5641, "馬公"),
      Time.zone.local(2026, 10, 26, 7, 30, 0)
    )
    modes = results.flat_map { |item|
      item["legs"].select { |leg| leg["kind"] == "ride" }.map { |leg| leg["mode"] }
    }.uniq

    assert_includes modes, "flight"
    assert_includes modes, "ferry"
  end

  test "round trips a graph through json" do
    graph = graph_with([
      route("blue", "藍線", "metro", [
        stop("a", "甲", 25.0, 121.5),
        stop("b", "乙", 25.02, 121.5)
      ], "daily" => { trips: [ [ 10 * 60, 10 * 60 + 12 ] ] })
    ])
    path = Rails.root.join("tmp/itinerary_graph_#{SecureRandom.hex(4)}.json")
    graph.write(path)
    loaded = Transit::Itinerary::Graph.load_file(path)
    itinerary = search(loaded, point(25.0, 121.5, "甲"), point(25.02, 121.5, "乙"), Time.zone.local(2026, 10, 24, 9, 50, 0)).first
    assert_equal "藍線", itinerary["legs"].first["name"]
  ensure
    FileUtils.rm_f(path) if path
  end

  def graph_with(patterns)
    Transit::Itinerary::Compiler.build(patterns:)
  end

  def route(id, name, mode, stops, services)
    { id:, name:, mode:, stops:, services: }
  end

  def stop(key, name, lat, lon, kind = "metro")
    { key:, name:, lat:, lon:, kind: }
  end

  def point(lat, lon, name)
    { "name" => name, "lat" => lat, "lon" => lon }
  end

  def search(graph, origin, destination, depart_at)
    Transit::Itinerary::Router.new(graph, origin:, destination:, depart_at:).call
  end
end
