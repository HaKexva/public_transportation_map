# frozen_string_literal: true

require "test_helper"

class Transit::ItineraryCorridorTest < ActiveSupport::TestCase
  test "splits a long trip into arrive / trunk / egress letters" do
    corridor = Transit::Itinerary::Corridor.call([ {
      "duration_minutes" => 200,
      "depart_at" => "2026-10-28T08:00:00+08:00",
      "arrive_at" => "2026-10-28T11:20:00+08:00",
      "legs" => [
        ride("bus", "和平高中", "台北車站", 20),
        ride("hsr", "台北", "左營", 100, "台灣高鐵"),
        ride("bus", "左營", "大鵬灣", 60)
      ]
    } ])

    ids = corridor["stages"].map { |stage| stage["id"] }
    titles = corridor["stages"].map { |stage| stage["title"] }

    assert_equal %w[A B C], ids
    assert_equal "抵達台北車站", titles[0]
    assert_match(/高鐵前往/, titles[1])
    assert_match(/轉接/, titles[2])
    assert_equal "shared", corridor["stages"][0]["kind"]
    assert_equal [ 0 ], corridor["stages"][0]["options"].first["itinerary_indexes"]
  end

  test "keeps alternate feeders to the same hub inside stage A" do
    corridor = Transit::Itinerary::Corridor.call([
      {
        "duration_minutes" => 360,
        "depart_at" => "2026-10-30T09:00:00+08:00",
        "arrive_at" => "2026-10-30T15:00:00+08:00",
        "legs" => [
          ride("bus", "安平古堡", "台南車站", 25, "102"),
          ride("rail", "臺南", "花蓮", 300, "台鐵"),
          ride("bus", "花蓮車站", "七星潭", 20, "花蓮公車")
        ]
      },
      {
        "duration_minutes" => 370,
        "depart_at" => "2026-10-30T09:00:00+08:00",
        "arrive_at" => "2026-10-30T15:10:00+08:00",
        "legs" => [
          ride("bus", "安平古堡", "建國路", 12, "102"),
          ride("bus", "建國路", "台南車站", 15, "10"),
          ride("rail", "臺南", "花蓮", 300, "台鐵"),
          ride("bus", "花蓮車站", "七星潭", 20, "花蓮公車")
        ]
      }
    ])

    by_id = corridor["stages"].index_by { |stage| stage["id"] }
    assert_equal %w[A B C], corridor["stages"].map { |stage| stage["id"] }
    assert_equal "choice", by_id["A"]["kind"]
    assert_equal 2, by_id["A"]["options"].length
    titles = by_id["A"]["options"].map { |option| option["title"] }
    assert_includes titles, "102 → 台南車站"
    assert_includes titles, "102→10 → 台南車站"
    assert_equal [ "台南車站" ], by_id["A"]["options"].map { |option| option["hub"] }.uniq
  end

  test "branches each stage with itinerary indexes so later picks lock to earlier hubs" do
    corridor = Transit::Itinerary::Corridor.call([
      {
        "duration_minutes" => 180,
        "depart_at" => "2026-10-28T08:00:00+08:00",
        "arrive_at" => "2026-10-28T11:00:00+08:00",
        "legs" => [
          ride("metro", "和平高中", "台北車站", 25, "文湖線"),
          ride("hsr", "台北", "左營", 100, "台灣高鐵"),
          ride("bus", "左營", "大鵬灣", 55, "左營客運")
        ]
      },
      {
        "duration_minutes" => 260,
        "depart_at" => "2026-10-28T08:00:00+08:00",
        "arrive_at" => "2026-10-28T12:20:00+08:00",
        "legs" => [
          ride("metro", "和平高中", "台北車站", 25, "文湖線"),
          ride("rail", "臺北", "高雄", 180, "自強號"),
          ride("bus", "高雄", "大鵬灣", 55, "高雄客運")
        ]
      },
      {
        "duration_minutes" => 190,
        "depart_at" => "2026-10-28T08:10:00+08:00",
        "arrive_at" => "2026-10-28T11:20:00+08:00",
        "legs" => [
          ride("metro", "公館", "台北車站", 20, "松山新店線"),
          ride("hsr", "台北", "左營", 100, "台灣高鐵"),
          ride("bus", "左營", "大鵬灣", 55, "左營客運")
        ]
      }
    ])

    by_id = corridor["stages"].index_by { |stage| stage["id"] }

    assert_equal "choice", by_id["A"]["kind"]
    assert_equal 2, by_id["A"]["options"].length
    assert_equal "抵達台北車站", by_id["A"]["title"]

    assert_equal "choice", by_id["B"]["kind"]
    assert_equal 2, by_id["B"]["options"].length
    hsr = by_id["B"]["options"].find { |option| option["mode"] == "hsr" }
    rail = by_id["B"]["options"].find { |option| option["mode"] == "rail" }
    assert_equal [ 0, 2 ], hsr["itinerary_indexes"]
    assert_equal [ 1 ], rail["itinerary_indexes"]

    assert_equal "choice", by_id["C"]["kind"]
    zuoying = by_id["C"]["options"].find { |option| option["legs"].any? { |leg| leg.dig("from", "name") == "左營" } }
    kaohsiung = by_id["C"]["options"].find { |option| option["legs"].any? { |leg| leg.dig("from", "name") == "高雄" } }
    assert_equal [ 0, 2 ], zuoying["itinerary_indexes"]
    assert_equal [ 1 ], kaohsiung["itinerary_indexes"]

    wenhu = by_id["A"]["options"].find { |option| option["title"].include?("文湖線") }
    compatible = wenhu["itinerary_indexes"] & hsr["itinerary_indexes"] & zuoying["itinerary_indexes"]
    assert_includes compatible, 0
    assert_empty wenhu["itinerary_indexes"] & rail["itinerary_indexes"] & zuoying["itinerary_indexes"]
  end

  test "merges metro feeders and local egress so a five-ride trip becomes A B C" do
    corridor = Transit::Itinerary::Corridor.call([ {
      "duration_minutes" => 220,
      "depart_at" => "2026-10-28T08:00:00+08:00",
      "arrive_at" => "2026-10-28T11:40:00+08:00",
      "legs" => [
        ride("metro", "動物園", "中山國中", 15, "文湖線"),
        ride("metro", "中山國中", "台北車站", 20, "淡水信義線"),
        ride("hsr", "台北", "左營", 100, "台灣高鐵"),
        ride("metro", "左營", "美麗島", 20, "紅線"),
        ride("bus", "美麗島", "大鵬灣", 50, "大鵬灣客運")
      ]
    } ])

    assert_equal %w[A B C], corridor["stages"].map { |stage| stage["id"] }
    assert_match(/文湖線/, corridor["stages"][0]["options"].first["title"])
    assert_match(/淡水信義線/, corridor["stages"][0]["options"].first["title"])
    assert_match(/高鐵/, corridor["stages"][1]["title"])
    assert_match(/紅線/, corridor["stages"][2]["options"].first["title"])
    assert_match(/大鵬灣客運/, corridor["stages"][2]["options"].first["title"])
  end

  test "labels a short major path as an A+B+C span instead of padding later stages" do
    corridor = Transit::Itinerary::Corridor.call([
      {
        "duration_minutes" => 180,
        "depart_at" => "2026-10-28T08:00:00+08:00",
        "arrive_at" => "2026-10-28T11:00:00+08:00",
        "legs" => [
          ride("metro", "公館", "台北車站", 20, "松山新店線"),
          ride("hsr", "台北", "左營", 100, "台灣高鐵"),
          ride("bus", "左營", "大鵬灣", 55, "左營客運")
        ]
      },
      {
        "duration_minutes" => 360,
        "depart_at" => "2026-10-28T08:00:00+08:00",
        "arrive_at" => "2026-10-28T14:00:00+08:00",
        "legs" => [
          ride("bus", "公館", "高雄", 300, "國道客運")
        ]
      }
    ])

    ids = corridor["stages"].map { |stage| stage["id"] }
    assert_equal %w[A B C], ids

    span = corridor["stages"][0]["options"].find { |option| option["id"].include?("+") }
    assert span, "expected a spanning coach option on stage A"
    assert_equal %w[A B C], span["covers"]
    assert_equal "A+B+C", span["id"]
    assert_includes span["itinerary_indexes"], 1

    b_indexes = corridor["stages"][1]["options"].flat_map { |option| option["itinerary_indexes"] }.uniq.sort
    assert_equal [ 0 ], b_indexes
  end

  test "pairs island ferry and flight on the same stage letter" do
    corridor = Transit::Itinerary::Corridor.call([
      {
        "duration_minutes" => 380,
        "depart_at" => "2026-11-01T08:00:00+08:00",
        "arrive_at" => "2026-11-01T14:20:00+08:00",
        "legs" => [
          ride("metro", "台北車站", "松山機場", 25, "文湖線"),
          ride("flight", "台北松山機場", "澎湖馬公機場", 55, "松山－馬公"),
          ride("bus", "澎湖馬公機場", "馬公商港", 20, "004")
        ]
      },
      {
        "duration_minutes" => 510,
        "depart_at" => "2026-11-01T08:00:00+08:00",
        "arrive_at" => "2026-11-01T16:30:00+08:00",
        "legs" => [
          ride("hsr", "台北", "左營", 100, "台灣高鐵"),
          ride("metro", "左營", "哈瑪星", 20, "橘線"),
          ride("ferry", "新濱碼頭", "馬公商港", 330, "高雄－馬公渡輪")
        ]
      }
    ])

    by_id = corridor["stages"].index_by { |stage| stage["id"] }
    assert_equal %w[A B C], corridor["stages"].map { |stage| stage["id"] }

    water = by_id["B"]["options"]
    assert water.any? { |option| option["mode"] == "flight" }, "expected flight on B"
    assert water.any? { |option| option["mode"] == "ferry" }, "expected ferry on B"
    ferry = water.find { |option| option["mode"] == "ferry" }
    assert_includes ferry["covers"], "B"
    assert_includes ferry["covers"], "C"
  end

  test "秋紅谷式 hub tree: A choices, A+B coach span, B continues_from, C after B" do
    corridor = Transit::Itinerary::Corridor.call([
      {
        "duration_minutes" => 420,
        "depart_at" => "2026-10-28T08:00:00+08:00",
        "arrive_at" => "2026-10-28T15:00:00+08:00",
        "legs" => [
          ride("bus", "秋紅谷", "台中車站", 25, "333"),
          ride("rail", "台中", "新烏日", 15, "台鐵"),
          ride("hsr", "新烏日", "左營", 90, "台灣高鐵"),
          ride("rail", "左營", "知本", 120, "台鐵"),
          ride("bus", "知本", "豐田", 40, "公車")
        ]
      },
      {
        "duration_minutes" => 430,
        "depart_at" => "2026-10-28T08:00:00+08:00",
        "arrive_at" => "2026-10-28T15:10:00+08:00",
        "legs" => [
          ride("bus", "秋紅谷", "高鐵台中站", 35, "公車"),
          ride("hsr", "高鐵台中", "左營", 90, "台灣高鐵"),
          ride("rail", "左營", "知本", 120, "台鐵"),
          ride("bus", "知本", "豐田", 40, "公車")
        ]
      },
      {
        "duration_minutes" => 500,
        "depart_at" => "2026-10-28T08:00:00+08:00",
        "arrive_at" => "2026-10-28T16:20:00+08:00",
        "legs" => [
          ride("bus", "秋紅谷", "台中車站", 25, "333"),
          ride("rail", "台中", "高雄", 210, "台鐵"),
          ride("rail", "高雄", "知本", 100, "台鐵"),
          ride("bus", "知本", "豐田", 40, "公車")
        ]
      },
      {
        "duration_minutes" => 450,
        "depart_at" => "2026-10-28T08:00:00+08:00",
        "arrive_at" => "2026-10-28T15:30:00+08:00",
        "legs" => [
          ride("bus", "秋紅谷", "建國客運站", 280, "國道客運"),
          ride("rail", "高雄", "知本", 100, "台鐵"),
          ride("bus", "知本", "豐田", 40, "公車")
        ]
      }
    ])

    by_id = corridor["stages"].index_by { |stage| stage["id"] }
    assert_equal %w[A B C D], corridor["stages"].map { |stage| stage["id"] }

    a_by_hub = by_id["A"]["options"].index_by { |option| option["hub"] }
    assert a_by_hub["新烏日"], "A to 新烏日"
    assert a_by_hub["高鐵台中"], "A to 高鐵台中"
    assert a_by_hub["台中車站"], "A-3 style access only to 台中車站"
    span = by_id["A"]["options"].find { |option| option["id"].include?("+") }
    assert_equal "建國客運站", span["hub"]
    assert_equal %w[A B], span["covers"]
    assert_equal "A+B", span["id"]
    refute_includes a_by_hub["台中車站"]["id"], "+"

    b_opts = by_id["B"]["options"]
    hsr = b_opts.find { |option| option["mode"] == "hsr" }
    rail = b_opts.find { |option| option["mode"] == "rail" }
    assert hsr
    assert rail
    assert_includes hsr["continues_from"], a_by_hub["新烏日"]["id"]
    assert_includes hsr["continues_from"], a_by_hub["高鐵台中"]["id"]
    assert_includes rail["continues_from"], a_by_hub["台中車站"]["id"]
    refute_includes rail["continues_from"], a_by_hub["新烏日"]["id"]

    c_opts = by_id["C"]["options"]
    assert c_opts.all? { |option| option["mode"] == "rail" }
    assert c_opts.any? { |option| option["continues_from"].include?(hsr["id"]) }
    assert c_opts.any? { |option| option["continues_from"].include?(rail["id"]) }
    assert c_opts.any? { |option| option["continues_from"].include?(span["id"]) }

    d_opts = by_id["D"]["options"]
    assert d_opts.all? { |option| option["mode"] == "bus" }
    assert d_opts.any? { |option| option["continues_from"].intersect?(c_opts.map { |row| row["id"] }) }
  end

  test "lets paths that meet at a hub combine across itineraries" do
    corridor = Transit::Itinerary::Corridor.call([
      {
        "duration_minutes" => 160,
        "depart_at" => "2026-10-28T08:00:00+08:00",
        "arrive_at" => "2026-10-28T10:40:00+08:00",
        "legs" => [
          ride("metro", "和平高中", "台北車站", 25, "文湖線"),
          ride("hsr", "台北", "左營", 100, "台灣高鐵")
        ]
      },
      {
        "duration_minutes" => 170,
        "depart_at" => "2026-10-28T08:00:00+08:00",
        "arrive_at" => "2026-10-28T10:50:00+08:00",
        "legs" => [
          ride("metro", "公館", "台北車站", 20, "松山新店線"),
          ride("rail", "臺北", "高雄", 150, "自強號")
        ]
      }
    ])

    by_id = corridor["stages"].index_by { |stage| stage["id"] }
    wenhu = by_id["A"]["options"].find { |option| option["title"].include?("文湖線") }
    hsr = by_id["B"]["options"].find { |option| option["mode"] == "hsr" }
    rail = by_id["B"]["options"].find { |option| option["mode"] == "rail" }

    assert_equal "台北車站", wenhu["hub"]
    assert_equal "台北車站", rail["from_hub"]
    assert_equal "台北車站", hsr["from_hub"]
    assert_equal [ 1 ], rail["itinerary_indexes"]
    assert_includes rail["connects_from"].map { |row| row["itinerary_index"] }, 0
    assert_includes rail["connects_from"].map { |row| row["itinerary_index"] }, 1
  end

  def ride(mode, from, to, minutes, name = mode)
    {
      "kind" => "ride",
      "mode" => mode,
      "name" => name,
      "route_id" => "#{mode}-#{name}",
      "minutes" => minutes,
      "from" => { "name" => from },
      "to" => { "name" => to }
    }
  end
end
