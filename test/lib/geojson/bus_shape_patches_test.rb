# frozen_string_literal: true

require "test_helper"

class Geojson::BusShapePatchesTest < ActiveSupport::TestCase
  STOP = [ 121.5921, 25.07185 ].freeze
  CIRCULATION = Geojson::BusShapePatches::STOP_CIRCULATIONS.fetch("三總內湖站")

  test "replaces a hospital visit from 成功路 with the internal loop and drops entrance spikes" do
    line = [
      [ 121.5899, 25.0740 ], [ 121.58981, 25.07174 ],
      [ 121.5910, 25.07170 ], [ 121.5920, 25.07155 ], [ 121.5920, 25.07235 ], [ 121.5910, 25.07195 ],
      [ 121.58988, 25.07197 ], [ 121.58972, 25.07161 ], [ 121.58971, 25.07183 ], [ 121.58972, 25.07161 ],
      [ 121.5905, 25.0690 ]
    ]
    data = collection(route(0, line), station(0, "三總內湖站", STOP))

    assert Geojson::BusShapePatches.process_collection!(data)

    patched = data["features"].first.dig("geometry", "coordinates")
    assert_equal line.first(2), patched.first(2)
    assert_equal CIRCULATION[:paths][:west], patched[2, CIRCULATION[:paths][:west].length]
    assert_equal [ [ 121.58988, 25.07197 ], [ 121.58972, 25.07161 ], [ 121.5905, 25.0690 ] ], patched.last(3)

    assert_not Geojson::BusShapePatches.process_collection!(data)
  end

  test "routes the arrival into 萬芳社區 through the bus lot instead of across the block" do
    terminal = Geojson::BusShapePatches::TERMINAL_APPROACHES.find { |entry| entry[:name] == "萬芳社區" }
    line = [ [ 121.568900, 25.002420 ], [ 121.569813, 25.002290 ], [ 121.570480, 25.001756 ] ]
    data = collection(route(1, line))

    assert Geojson::BusShapePatches.process_collection!(data)
    assert_equal line.first(2) + terminal[:path] + [ line.last ], data["features"].first.dig("geometry", "coordinates")
    assert_not Geojson::BusShapePatches.process_collection!(data)
  end

  test "311 short-turn continues past Shuiyuan Market over Fuhe Bridge to Linsen Road" do
    turnaround = Geojson::BusShapePatches::TURNAROUNDS.fetch("taipei_311sh").first
    line = [
      [ 121.534517, 25.014305 ],
      [ 121.535325, 25.013669 ],
      turnaround[:from].dup
    ]
    data = {
      "type" => "FeatureCollection",
      "properties" => { "id" => "taipei_311sh" },
      "features" => [ route(0, line) ]
    }

    assert Geojson::BusShapePatches.process_collection!(data)

    patched = data["features"].first.dig("geometry", "coordinates")
    assert_equal line.first(2), patched.first(2)
    assert_in_delta turnaround[:path].last[0], patched.last[0], 0.00001
    assert_in_delta turnaround[:path].last[1], patched.last[1], 0.00001
    assert_operator patched.length, :>, line.length + 20
    assert_not Geojson::BusShapePatches.process_collection!(data)
  end

  test "紅55區 short-turn reverses from Taipei City University of Science and Technology to Xueyuan Rd" do
    turnaround = Geojson::BusShapePatches::TURNAROUNDS.fetch("taipei_hong55sh").first
    line = [
      [ 121.466216, 25.131778 ],
      [ 121.46750, 25.13270 ],
      turnaround[:from].dup
    ]
    data = {
      "type" => "FeatureCollection",
      "properties" => { "id" => "taipei_hong55sh" },
      "features" => [ route(0, line) ]
    }

    assert Geojson::BusShapePatches.process_collection!(data)

    patched = data["features"].first.dig("geometry", "coordinates")
    assert_equal line.first(2), patched.first(2)
    assert_in_delta turnaround[:path].last[0], patched.last[0], 0.00001
    assert_in_delta turnaround[:path].last[1], patched.last[1], 0.00001
    assert_operator patched.length, :>, line.length + 40
    assert_not Geojson::BusShapePatches.process_collection!(data)
  end

  test "953 short-turn continues past NTUT along the main inbound to Fujing" do
    turnaround = Geojson::BusShapePatches::SIBLING_TURNAROUNDS.fetch("new_taipei_953sh").first
    sibling = Geojson::BusLayout.find_geojson("new_taipei_953")
    skip "new_taipei_953.geojson missing" unless sibling&.exist?

    tip = turnaround[:from]
    line = [ [ 121.53310, 25.04218 ], tip.dup ]
    inbound = [
      route(1, [ tip.dup, turnaround[:until].dup, [ 121.62556, 25.22012 ] ]),
      station(1, "富景天下社區", turnaround[:until].dup)
    ]
    data = {
      "type" => "FeatureCollection",
      "properties" => { "id" => "new_taipei_953sh" },
      "features" => [ route(0, line), *inbound ]
    }

    assert Geojson::BusShapePatches.process_collection!(data)

    patched = data["features"].first.dig("geometry", "coordinates")
    assert_equal line.first, patched.first
    assert_in_delta turnaround[:until][0], patched.last[0], 0.0005
    assert_in_delta turnaround[:until][1], patched.last[1], 0.0005
    assert_operator patched.length, :>, line.length + 50
    assert_not Geojson::BusShapePatches.process_collection!(data)
  end

  test "682 Bali tips meet at the shared 淡水客運八里站 bay" do
    patches = Geojson::BusShapePatches::PATCHES.fetch("taipei_682")
    outbound = patches.find { |entry| entry[:direction] == 0 }
    inbound = patches.find { |entry| entry[:direction] == 1 }
    dir0 = [
      outbound[:from].dup,
      [ 121.40651144273548, 25.15317427837808 ],
      [ 121.40727477248456, 25.15248464909135 ],
      outbound[:to].dup,
      [ 121.408152, 25.1516193 ],
      [ 121.4081417, 25.1515833 ]
    ]
    dir1 = [
      [ 121.4052251, 25.1542468 ],
      inbound[:from].dup,
      inbound[:to].dup
    ]
    data = {
      "type" => "FeatureCollection",
      "properties" => { "id" => "taipei_682" },
      "features" => [ route(0, dir0), route(1, dir1) ]
    }

    assert Geojson::BusShapePatches.process_collection!(data)

    out = data["features"][0].dig("geometry", "coordinates")
    back = data["features"][1].dig("geometry", "coordinates")
    assert_equal outbound[:path].first, out.first
    assert_equal inbound[:path].last, back.last
    assert_in_delta out.first[0], back.last[0], 0.00001
    assert_in_delta out.first[1], back.last[1], 0.00001
    assert_operator Geojson::BusLoopCloser.meters_between(out.first, back.last), :<, 1
    assert_not Geojson::BusShapePatches.process_collection!(data)
  end

  test "672 short-turn continues past Gongguan along Roosevelt, Xinsheng, Xinhai and Keelung" do
    turnaround = Geojson::BusShapePatches::TURNAROUNDS.fetch("taipei_672sh").first
    line = [
      [ 121.5360921, 25.0129968 ],
      [ 121.53562, 25.0135368 ],
      [ 121.53517905593269, 25.013983623776447 ]
    ]
    data = {
      "type" => "FeatureCollection",
      "properties" => { "id" => "taipei_672sh" },
      "features" => [ route(0, line) ]
    }

    assert Geojson::BusShapePatches.process_collection!(data)

    patched = data["features"].first.dig("geometry", "coordinates")
    assert_equal line.first(2), patched.first(2)
    assert_in_delta turnaround[:path].last[0], patched.last[0], 0.00001
    assert_in_delta turnaround[:path].last[1], patched.last[1], 0.00001
    assert patched.any? { |point| Geojson::BusLoopCloser.meters_between(point, [ 121.5341982, 25.0208673 ]) < 5 }
    assert_not Geojson::BusShapePatches.process_collection!(data)
  end

  test "589 Nangang terminus exits the bay onto Nangang Road by the admin centre" do
    rewrites = Geojson::BusShapePatches::TERMINUS_REWRITES.fetch("new_taipei_589")
    outbound = rewrites.find { |entry| entry[:side] == :end }
    inbound = rewrites.find { |entry| entry[:side] == :start }
    # Pre-patch TDX: chord north out of the bay, return jumps past 行政中心.
    dir0 = [
      [ 121.607558, 25.053395 ], [ 121.606598, 25.053251 ], [ 121.606560, 25.053250 ],
      [ 121.606522, 25.053258 ], [ 121.606488, 25.053274 ], [ 121.606459, 25.053297 ],
      [ 121.606439, 25.053327 ], [ 121.606427, 25.053360 ],
      [ 121.606245, 25.054230 ], [ 121.606231, 25.054243 ]
    ]
    dir1 = [
      [ 121.606231, 25.054243 ], [ 121.609262, 25.054780 ], [ 121.612012, 25.055220 ]
    ]
    data = {
      "type" => "FeatureCollection",
      "properties" => { "id" => "new_taipei_589" },
      "features" => [ route(0, dir0), route(1, dir1) ]
    }

    assert Geojson::BusShapePatches.process_collection!(data)

    out = data["features"][0].dig("geometry", "coordinates")
    back = data["features"][1].dig("geometry", "coordinates")
    assert_equal outbound[:path].last, out.last
    assert_equal inbound[:path].first, back.first
    assert_in_delta outbound[:path].last[0], back.first[0], 0.00001
    assert_in_delta outbound[:path].last[1], back.first[1], 0.00001
    assert_operator out.length, :>, dir0.length
    assert_operator Geojson::BusLoopCloser.meters_between(back[1], [ 121.60712, 25.05433 ]), :<, 5
    assert_not Geojson::BusShapePatches.process_collection!(data)
  end

  test "508 short-turn outbound starts at Luzhou Terminal instead of Luzhou Station" do
    trim = Geojson::BusShapePatches::START_TRIMS.fetch("taipei_508sh").first
    luzhou_station = [ 121.469180, 25.078562 ]
    terminal = trim[:at]
    after = [ 121.467428, 25.087301 ]
    line = [
      luzhou_station,
      [ 121.469423, 25.079195 ],
      [ 121.467428, 25.087299 ],
      terminal.dup,
      after.dup,
      [ 121.470722, 25.082783 ]
    ]
    data = {
      "type" => "FeatureCollection",
      "properties" => { "id" => "taipei_508sh" },
      "features" => [ route(0, line) ]
    }

    assert Geojson::BusShapePatches.process_collection!(data)

    patched = data["features"].first.dig("geometry", "coordinates")
    assert_in_delta terminal[0], patched.first[0], 0.00001
    assert_in_delta terminal[1], patched.first[1], 0.00001
    assert_equal [ after, [ 121.470722, 25.082783 ] ], patched.last(2)
    assert_not Geojson::BusShapePatches.process_collection!(data)
  end

  test "712 stops at 捷運亞東醫院站 instead of the 貴興路 tip" do
    end_at = Geojson::BusShapePatches::END_TRIMS.fetch("new_taipei_712").first[:at]
    start_at = Geojson::BusShapePatches::START_TRIMS.fetch("new_taipei_712").first[:at]
    tip = [ 121.453536, 25.001350 ]
    outbound = [
      [ 121.451067, 24.994351 ],
      [ 121.452554, 24.998335 ],
      tip.dup
    ]
    inbound = [
      tip.dup,
      [ 121.452945, 24.999586 ],
      [ 121.452529, 24.998349 ],
      [ 121.451203, 24.994788 ]
    ]
    data = {
      "type" => "FeatureCollection",
      "properties" => { "id" => "new_taipei_712" },
      "features" => [ route(0, outbound), route(1, inbound) ]
    }

    assert Geojson::BusShapePatches.process_collection!(data)

    out = data["features"][0].dig("geometry", "coordinates")
    back = data["features"][1].dig("geometry", "coordinates")
    assert_operator Geojson::BusLoopCloser.meters_between(out.last, end_at), :<, 15
    assert_operator Geojson::BusLoopCloser.meters_between(back.first, start_at), :<, 40
    assert_operator Geojson::BusLoopCloser.meters_between(out.last, tip), :>, 100
    assert_operator Geojson::BusLoopCloser.meters_between(back.first, tip), :>, 100
    assert_not Geojson::BusShapePatches.process_collection!(data)
  end

  test "runs both halves of the 陽明山國家公園管理處 terminal loop" do
    terminal = Geojson::BusShapePatches::TERMINAL_LOOPS.find { |entry| entry[:name] == "陽明山國家公園管理處" }
    arrival = [ [ 121.546500, 25.154900 ], [ 121.546180, 25.155230 ], [ 121.546020, 25.155400 ],
                [ 121.545700, 25.155130 ], [ 121.544520, 25.154110 ], [ 121.544700, 25.153900 ] ]
    departure = [ [ 121.544700, 25.153900 ], [ 121.545400, 25.154000 ], [ 121.546070, 25.155220 ],
                  [ 121.546200, 25.155140 ], [ 121.546500, 25.154900 ] ]
    data = collection(route(0, arrival), route(1, departure))

    assert Geojson::BusShapePatches.process_collection!(data)
    patched_arrival, patched_departure = data["features"].map { |feature| feature.dig("geometry", "coordinates") }
    assert_equal arrival.first(2) + terminal[:arrival], patched_arrival
    assert_equal terminal[:departure] + departure.last(1), patched_departure
    assert_not Geojson::BusShapePatches.process_collection!(data)
  end

  test "runs a through route at 新北板橋公車站 along its platform" do
    lane = Geojson::BusShapePatches::BANQIAO_LANES.fetch("第四月台")
    boarding = Geojson::BusShapePatches::BANQIAO_BOARDING.fetch("第四月台")
    before = [ 121.4650, 25.0145 ]
    after = [ 121.4600, 25.0148 ]
    line = [ before, [ boarding[0] + 0.00035, boarding[1] ], after ]
    stop = station(0, "新北板橋公車站", [ 121.462239, 25.012817 ], "第四月台")
    data = collection(route(0, line), stop)

    assert Geojson::BusShapePatches.process_collection!(data, router: straight_router)

    assert_equal [ before ] + lane + [ after ], data["features"].first.dig("geometry", "coordinates")
    assert_equal boarding, stop.dig("geometry", "coordinates")
    assert_not Geojson::BusShapePatches.process_collection!(data, router: straight_router)
  end

  test "starts a departure from 新北板橋公車站 on the platform and ends an arrival there" do
    lane = Geojson::BusShapePatches::BANQIAO_LANES.fetch("第一月台")
    boarding = Geojson::BusShapePatches::BANQIAO_BOARDING.fetch("第一月台")
    boarding_at = lane.index(boarding)
    away = [ 121.4600, 25.0152 ]
    nearer = [ boarding[0] + 0.0003, boarding[1] ]
    data = collection(
      route(0, [ nearer, away ]), station(0, "新北板橋公車站", [ 121.462542, 25.012770 ], "第一月台"),
      route(1, [ [ 121.4652, 25.0140 ], nearer ]), station(1, "新北板橋公車站", [ 121.462542, 25.012770 ], "第一月台")
    )

    assert Geojson::BusShapePatches.process_collection!(data, router: straight_router)

    departed, arrived = data["features"].select { |feature| feature.dig("properties", "feature_type") == "route" }
    assert_equal lane[boarding_at..] + [ away ], departed.dig("geometry", "coordinates")
    assert_equal [ [ 121.4652, 25.0140 ] ] + lane[0..boarding_at], arrived.dig("geometry", "coordinates")
    assert_not Geojson::BusShapePatches.process_collection!(data, router: straight_router)
  end

  test "reclaims a Banqiao bay approach sealed onto 縣民大道 by join_termini" do
    boarding = Geojson::BusShapePatches::BANQIAO_BOARDING.fetch("第二月台")
    join = [ 121.465595, 25.014737 ]
    approach = [
      join.dup,
      [ 121.464752, 25.014111 ],
      [ 121.463887, 25.013442 ],
      [ 121.463292, 25.012990 ],
      [ 121.462764, 25.012694 ],
      boarding.dup
    ]
    leave = [ boarding.dup, [ 121.462125, 25.013331 ], [ 121.463800, 25.013114 ], [ 121.468627, 25.016640 ] ]
    outbound = [ [ 121.468095, 25.016485 ], join.dup ]
    inbound = approach + leave.drop(1)
    data = collection(
      route(0, outbound),
      station(0, "中山國中(縣民大道)", [ 121.468616, 25.016898 ]),
      route(1, inbound),
      station(1, "新北板橋公車站", boarding.dup, "第二月台"),
      station(1, "中山國中(縣民大道)", [ 121.469000, 25.016752 ])
    )
    data["properties"]["id"] = "new_taipei_963"
    data["properties"]["destination"] = "中山國中(縣民大道)"

    assert Geojson::BusShapePatches.process_collection!(data)

    out_line, in_line = data["features"].select { |feature| feature.dig("properties", "feature_type") == "route" }
      .map { |feature| feature.dig("geometry", "coordinates") }
    assert_in_delta boarding[0], out_line.last[0], 0.00005
    assert_in_delta boarding[1], out_line.last[1], 0.00005
    assert_in_delta boarding[0], in_line.first[0], 0.00005
    assert_in_delta boarding[1], in_line.first[1], 0.00005
    assert_equal "新北板橋公車站", data["properties"]["destination"]
    assert_equal "淡水客運", data["properties"]["operator_2"]
    assert data["features"].any? { |feature|
      feature.dig("properties", "feature_type") == "station" &&
        feature.dig("properties", "direction").to_s == "0" &&
        feature.dig("properties", "name") == "新北板橋公車站"
    }
    assert_not Geojson::BusShapePatches.process_collection!(data)
  end

  test "702 arrival tip joins the Banqiao bay even without a published stop" do
    lane = Geojson::BusShapePatches::BANQIAO_LANES.fetch("第三月台")
    boarding = Geojson::BusShapePatches::BANQIAO_BOARDING.fetch("第三月台")
    # Approach dies on 縣民大道 just outside the bay (live 702 tip).
    tip = [ 121.462882, 25.012562 ]
    away = [ 121.4600, 25.0140 ]
    data = collection(
      route(0, [ [ 121.4605, 25.0135 ], tip ]),
      route(1, [ tip, away ]),
      station(1, "新北板橋公車站", [ 121.462542, 25.012770 ], "第三月台")
    )
    data["properties"]["id"] = "new_taipei_702"

    assert Geojson::BusShapePatches.process_collection!(data, router: straight_router)

    outbound, inbound = data["features"].select { |feature| feature.dig("properties", "feature_type") == "route" }
    assert_in_delta boarding[0], outbound.dig("geometry", "coordinates").last[0], 0.00001
    assert_in_delta boarding[1], outbound.dig("geometry", "coordinates").last[1], 0.00001
    assert_in_delta boarding[0], inbound.dig("geometry", "coordinates").first[0], 0.00001
    assert_in_delta boarding[1], inbound.dig("geometry", "coordinates").first[1], 0.00001
    assert_includes outbound.dig("geometry", "coordinates"), lane.first
    assert_not Geojson::BusShapePatches.process_collection!(data, router: straight_router)
  end

  test "leaves directions that do not stop there alone" do
    line = [ [ 121.58981, 25.07174 ], [ 121.5915, 25.0712 ], [ 121.5950, 25.0708 ] ]
    data = collection(route(1, line), station(1, "將軍嶺", [ 121.5880, 25.0700 ]))

    assert_not Geojson::BusShapePatches.process_collection!(data)
  end

  test "splits 林口轉運站 boarding and alighting platforms" do
    boarding = Geojson::BusShapePatches::LINKOU_PLATFORMS.fetch("第5月台")
    alighting = Geojson::BusShapePatches::LINKOU_PLATFORMS.fetch("第8月台")
    away = [ 121.54857, 25.03829 ]
    data = collection(
      route(0, [ boarding, away ]),
      station(0, "林口轉運站", boarding.dup, "第5月台"),
      station(0, "仁愛敦化路口", away),
      route(1, [ away, boarding ]),
      station(1, "安和敦化路口", away),
      station(1, "林口轉運站", boarding.dup, "第5月台")
    )
    data["properties"]["id"] = "new_taipei_967sub"

    assert Geojson::BusShapePatches.process_collection!(data)

    outbound, inbound = data["features"].select { |feature| feature.dig("properties", "feature_type") == "station" && feature.dig("properties", "name") == "林口轉運站" }
    assert_equal "第5月台", outbound.dig("properties", "platform")
    assert_equal boarding, outbound.dig("geometry", "coordinates")
    assert_equal "第8月台", inbound.dig("properties", "platform")
    assert_equal alighting, inbound.dig("geometry", "coordinates")
    assert_equal alighting, data["features"][3].dig("geometry", "coordinates").last
    assert_not Geojson::BusShapePatches.process_collection!(data)
  end

  test "moves a 林口轉運站 departure off the alighting bay" do
    boarding = Geojson::BusShapePatches::LINKOU_PLATFORMS.fetch("第2月台")
    alighting = Geojson::BusShapePatches::LINKOU_PLATFORMS.fetch("第8月台")
    mid = [ 121.3600, 25.0700 ]
    data = collection(
      route(0, [ alighting, mid, alighting ]),
      station(0, "林口轉運站", alighting.dup, "第8月台"),
      station(0, "文化北路源泉街口", mid),
      station(0, "林口轉運站", alighting.dup, "第8月台")
    )
    data["properties"]["id"] = "new_taipei_760"

    assert Geojson::BusShapePatches.process_collection!(data)

    first, last = data["features"].select { |feature| feature.dig("properties", "feature_type") == "station" && feature.dig("properties", "name") == "林口轉運站" }
    assert_equal "第2月台", first.dig("properties", "platform")
    assert_equal boarding, first.dig("geometry", "coordinates")
    assert_equal "第8月台", last.dig("properties", "platform")
    assert_equal alighting, last.dig("geometry", "coordinates")
    assert_equal boarding, data["features"].first.dig("geometry", "coordinates").first
    assert_not Geojson::BusShapePatches.process_collection!(data)
  end

  test "maps 786 through 林口轉運站 onto Wikipedia boarding platforms" do
    bay1 = Geojson::BusShapePatches::LINKOU_PLATFORMS.fetch("第1月台")
    bay3 = Geojson::BusShapePatches::LINKOU_PLATFORMS.fetch("第3月台")
    alighting = Geojson::BusShapePatches::LINKOU_PLATFORMS.fetch("第8月台")
    west = [ 121.3550, 25.0680 ]
    east = [ 121.3700, 25.0680 ]
    data = collection(
      route(0, [ west, alighting.dup, east ]),
      station(0, "華亞園區", west),
      station(0, "林口轉運站", alighting.dup, "第8月台"),
      station(0, "萬坪公園", east),
      route(1, [ east, alighting.dup, west ]),
      station(1, "萬坪公園", east),
      station(1, "林口轉運站", alighting.dup, "第9月台"),
      station(1, "華亞園區", west)
    )
    data["properties"]["id"] = "new_taipei_786"

    assert Geojson::BusShapePatches.process_collection!(data)

    outbound, inbound = data["features"].select { |feature|
      feature.dig("properties", "feature_type") == "station" && feature.dig("properties", "name") == "林口轉運站"
    }
    assert_equal "第1月台", outbound.dig("properties", "platform")
    assert_equal bay1, outbound.dig("geometry", "coordinates")
    assert_equal "第3月台", inbound.dig("properties", "platform")
    assert_equal bay3, inbound.dig("geometry", "coordinates")
    assert_equal bay1, data["features"][0].dig("geometry", "coordinates")[1]
    assert_equal bay3, data["features"][4].dig("geometry", "coordinates")[1]
    assert_not Geojson::BusShapePatches.process_collection!(data)
  end

  test "drops the 237 main-line spur out to 政大圖書館 and back" do
    leave = [ 121.576044, 24.987821 ]
    tip = [ 121.576910, 24.986166 ]
    line = [
      [ 121.5770, 24.9890 ], leave, [ 121.5765, 24.9870 ], tip, [ 121.5766, 24.9872 ], leave, [ 121.5768, 24.9885 ]
    ]
    library = station(0, "政大圖書館", tip)
    kept = station(0, "政大一", leave)
    data = collection(route(0, line), library, kept)
    data["properties"]["id"] = "taipei_237"

    assert Geojson::BusShapePatches.process_collection!(data)

    patched = data["features"].find { |feature| feature.dig("properties", "feature_type") == "route" }
    assert_equal [ line[0], leave, leave, line[-1] ], patched.dig("geometry", "coordinates")
    names = data["features"].select { |feature| feature.dig("properties", "feature_type") == "station" }
      .map { |feature| feature.dig("properties", "name") }
    assert_equal [ "政大一" ], names
    assert_not Geojson::BusShapePatches.process_collection!(data)
  end

  test "drops the retired 963 express spur onto 成泰路高架 after 五府千歲" do
    leave0 = [ 121.4488033, 25.0958009 ]
    tip0 = [ 121.4477302, 25.0861966 ]
    leave1 = [ 121.4517088, 25.1007666 ]
    tip1 = [ 121.447948, 25.0845435 ]
    outbound = [
      [ 121.4504, 25.0986 ], leave0, [ 121.4481, 25.0905 ], tip0, [ 121.4481, 25.0905 ], leave0, [ 121.4469, 25.0939 ]
    ]
    inbound = [
      [ 121.4469, 25.0939 ], leave1, [ 121.4482, 25.0909 ], tip1, [ 121.4482, 25.0909 ], leave1, [ 121.4504, 25.0986 ]
    ]
    data = collection(route(0, outbound), route(1, inbound))
    data["properties"]["id"] = "new_taipei_963"
    data["properties"]["destination"] = "新北板橋公車站"
    data["properties"]["operator_2"] = "淡水客運"

    assert Geojson::BusShapePatches.process_collection!(data)

    out_line, in_line = data["features"].select { |feature| feature.dig("properties", "feature_type") == "route" }
      .map { |feature| feature.dig("geometry", "coordinates") }
    assert_equal [ outbound[0], leave0, leave0, outbound[-1] ], out_line
    assert_equal [ inbound[0], leave1, leave1, inbound[-1] ], in_line
    assert out_line.none? { |point| point == tip0 }
    assert in_line.none? { |point| point == tip1 }
    assert_not Geojson::BusShapePatches.process_collection!(data)
  end

  test "keeps the 崁頂 loop on 249本線 and straightens the skip variant" do
    stops = Geojson::BusShapePatches::KANDING_STOPS
    leave = Geojson::BusShapePatches::KANDING_LEAVE
    back = Geojson::BusShapePatches::KANDING_BACK
    tip = Geojson::BusShapePatches::KANDING_TIP
    loop = [ leave, stops[0][:coordinates], tip, stops[2][:coordinates], back ]
    direct = Geojson::BusShapePatches::KANDING_DIRECT

    main = collection(route(1, loop), station(1, "崁頂(中華路)", leave))
    main["properties"]["id"] = Geojson::BusShapePatches::KANDING_MAIN_ID
    main["properties"]["name"] = "249"
    main["properties"]["color"] = "#9333EA"

    assert Geojson::BusShapePatches.process_collection!(main)
    main_names = main["features"].select { |feature| feature.dig("properties", "feature_type") == "station" }
      .map { |feature| feature.dig("properties", "name") }
    assert_equal [ "崁頂(中華路)", "崁頂", "螢橋國小", "重慶南路三段(中正橋)" ], main_names
    assert_not Geojson::BusShapePatches.process_collection!(main)

    skip = collection(
      route(1, loop),
      station(1, "崁頂", stops[0][:coordinates]),
      station(1, "螢橋國小", tip),
      station(1, "重慶南路三段(中正橋)", stops[2][:coordinates]),
      station(1, "捷運頂溪站", [ 121.515471, 25.013998 ])
    )
    skip["properties"]["id"] = Geojson::BusShapePatches::KANDING_SKIP_ID

    assert Geojson::BusShapePatches.process_collection!(skip)
    patched = skip["features"].find { |feature| feature.dig("properties", "feature_type") == "route" }
    assert_equal [ leave ] + direct + [ back ], patched.dig("geometry", "coordinates")
    kept = skip["features"].select { |feature| feature.dig("properties", "feature_type") == "station" }
      .map { |feature| feature.dig("properties", "name") }
    assert_equal [ "捷運頂溪站" ], kept
    assert_not Geojson::BusShapePatches.process_collection!(skip)
  end

  test "adds the 花鐘 out-and-back stops on 260區" do
    point = Geojson::BusShapePatches::FLOWER_POINT
    line = [ [ 121.54603, 25.15148 ], point, [ 121.54742, 25.1525 ] ]
    data = collection(
      route(0, line),
      station(0, "陽明山總站", line.first),
      station(0, "陽明山", line.last),
      route(1, line.reverse),
      station(1, "陽明山", line.last),
      station(1, "陽明山總站", line.first)
    )
    data["properties"]["id"] = Geojson::BusShapePatches::FLOWER_ROUTE_ID
    data["properties"]["name"] = "260區"
    data["properties"]["color"] = "#7CB342"

    assert Geojson::BusShapePatches.process_collection!(data)
    names = data["features"].select { |feature| feature.dig("properties", "feature_type") == "station" }
      .group_by { |feature| feature.dig("properties", "direction") }
      .transform_values { |features| features.map { |feature| feature.dig("properties", "name") } }
    assert_equal [
      "陽明山總站", "頂坪", "陽明山立體停車場(草山行館)", "第一停車場(花鐘)",
      "陽明山立體停車場(草山行館)", "頂坪", "橫嶺古道", "第二接續井", "陽明山"
    ], names[0]
    assert_equal [
      "陽明山", "頂坪", "陽明山立體停車場(草山行館)", "第一停車場(花鐘)",
      "陽明山立體停車場(草山行館)", "頂坪", "橫嶺古道", "陽明山總站"
    ], names[1]
    assert_not Geojson::BusShapePatches.process_collection!(data)

    far = collection(route(0, [ [ 121.50, 25.04 ], [ 121.51, 25.05 ] ]), station(0, "陽明山", [ 121.51, 25.05 ]))
    far["properties"]["id"] = Geojson::BusShapePatches::FLOWER_ROUTE_ID
    assert_not Geojson::BusShapePatches.process_collection!(far)
  end

  test "drops a detour loop between the first and last pass of its junction" do
    junction = [ 121.583855, 25.038199 ]
    loop = [ [ 121.5830, 25.0400 ], [ 121.5800, 25.0420 ], [ 121.5780, 25.0380 ], [ 121.5820, 25.0376 ] ]
    line = [ [ 121.5870, 25.0392 ], junction ] + loop + [ [ 121.583894, 25.038110 ], [ 121.5800, 25.0366 ] ]

    patched = Geojson::BusShapePatches.drop_excursion(line, junction)

    assert_equal [ [ 121.5870, 25.0392 ], junction, [ 121.5800, 25.0366 ] ], patched
    assert_equal line, Geojson::BusShapePatches.drop_excursion(line, [ 121.60, 25.05 ])
  end

  test "follows the roads through 公館 instead of the removed roundabout" do
    center = Geojson::BusShapePatches::GONGGUAN_CENTER
    approach = [ center[0] - 0.00050, center[1] + 0.00055 ]
    leave = [ center[0] + 0.00070, center[1] + 0.00036 ]
    south = [ center[0], center[1] - 0.00040 ]
    west = [ center[0] - 0.00045, center[1] ]
    east = [ center[0] + 0.00045, center[1] ]
    line = [ approach, west, south, east, leave ]
    elsewhere = [ [ 121.50, 25.04 ], [ 121.51, 25.05 ] ]
    data = collection(route(0, line), route(1, elsewhere))

    assert Geojson::BusShapePatches.process_collection!(data, router: straight_router)

    patched = data["features"].first.dig("geometry", "coordinates")
    assert_equal [ approach, leave ], patched
    assert_not_includes patched, south
    assert_equal elsewhere, data["features"].last.dig("geometry", "coordinates")
    assert_not Geojson::BusShapePatches.process_collection!(data, router: straight_router)
  end

  test "615 reaches 臺大醫院 along Zhongshan South Road and leaves on Xuzhou Road" do
    hospital = [ 121.518655, 25.042420 ]
    data = {
      "type" => "FeatureCollection",
      "properties" => { "id" => "taipei_615" },
      "features" => [
        route(0, [
          [ 121.519848, 25.046464 ],
          [ 121.51916834841846, 25.04469562794997 ],
          [ 121.518585469085, 25.042634526437475 ],
          [ 121.51851298930704, 25.042415638989244 ]
        ]),
        route(1, [
          [ 121.518585469085, 25.042634526437475 ],
          [ 121.5182370859609, 25.040476500547683 ],
          [ 121.5186027121637, 25.04173151965815 ],
          [ 121.51874824561705, 25.04180876365537 ],
          [ 121.5221942393795, 25.040981253026267 ]
        ]),
        station(0, "臺大醫院", [ 121.51846488093777, 25.042525923467416 ]),
        station(1, "臺大醫院", [ 121.5185552467, 25.041403318287 ])
      ]
    }

    assert Geojson::BusShapePatches.process_collection!(data)

    outbound = data["features"][0].dig("geometry", "coordinates")
    inbound = data["features"][1].dig("geometry", "coordinates")
    assert_equal hospital, outbound.last
    assert_equal hospital, inbound.first
    assert_in_delta 121.518860, outbound[-2][0], 0.00001
    refute inbound.any? { |point| point[1] < 25.0412 && point[0] < 121.5184 }
    assert inbound.any? { |point| (point[0] - 121.52024).abs < 0.0001 && (point[1] - 25.04150).abs < 0.0001 }
    assert_equal hospital, data["features"][2].dig("geometry", "coordinates")
    assert_equal [ 121.518687, 25.041809 ], data["features"][3].dig("geometry", "coordinates")
    assert_not Geojson::BusShapePatches.process_collection!(data)
  end

  test "823 flattens the 南港展覽館 north bulge and separates the three 橫科 poles" do
    out_line = [
      [ 121.6214, 25.0540 ], [ 121.6197, 25.0563 ],
      [ 121.6200, 25.0575 ], [ 121.6195, 25.0590 ], [ 121.6168, 25.0585 ], [ 121.6166, 25.0552 ],
      [ 121.6180, 25.0549 ], [ 121.6214, 25.0548 ], [ 121.6300, 25.0555 ]
    ]
    in_line = [
      [ 121.6300, 25.0555 ], [ 121.6217, 25.0550 ], [ 121.6173, 25.0551 ],
      [ 121.6168, 25.0580 ], [ 121.6195, 25.0590 ], [ 121.6203, 25.0575 ],
      [ 121.6214, 25.0548 ], [ 121.6194, 25.0498 ]
    ]
    data = {
      "type" => "FeatureCollection",
      "properties" => { "id" => "new_taipei_823", "ref" => "823" },
      "features" => [
        route(0, out_line),
        route(1, in_line),
        station(0, "橫科", [ 121.62138, 25.05483 ]),
        station(1, "橫科", [ 121.62191, 25.055038 ]),
        station(1, "橫科", [ 121.621447, 25.054811 ])
      ]
    }

    assert Geojson::BusShapePatches.process_collection!(data)

    out = data["features"].find { |feature| feature.dig("properties", "direction") == 0 && feature.dig("geometry", "type") == "LineString" }
      .dig("geometry", "coordinates")
    assert out.none? { |point| point[1] > 25.0572 }, "outbound exhibition loop stays on 經貿一路"
    assert_operator out.index { |point| point == [ 121.6197, 25.0563 ] }, :<,
      out.index { |point| (point[0] - 121.6180).abs < 0.0002 && (point[1] - 25.0549).abs < 0.0002 }

    hengke = data["features"].select { |feature| feature.dig("properties", "name") == "橫科" }
    assert_equal [ "往汐止", "往南港展覽館", "往舊莊" ], hengke.map { |feature| feature.dig("properties", "note") }
    assert_equal 3, hengke.map { |feature| feature.dig("geometry", "coordinates") }.uniq.length

    out_hengke = hengke.find { |feature| feature.dig("properties", "direction") == 0 }
    expo_out_idx = out.index { |point| (point[0] - 121.6180).abs < 0.0002 && (point[1] - 25.0549).abs < 0.0002 }
    out_hengke_idx = out.each_index.min_by { |index|
      dx = out[index][0] - out_hengke.dig("geometry", "coordinates")[0]
      dy = out[index][1] - out_hengke.dig("geometry", "coordinates")[1]
      dx * dx + dy * dy
    }
    assert_operator out_hengke_idx, :>, expo_out_idx, "outbound 橫科 sits on the post-loop eastbound passage"

    inbound = data["features"].select { |feature| feature.dig("properties", "direction") == 1 && feature.dig("properties", "name") == "橫科" }
    in_line = data["features"].find { |feature| feature.dig("properties", "direction") == 1 && feature.dig("geometry", "type") == "LineString" }
      .dig("geometry", "coordinates")
    in_idxs = inbound.map { |stop|
      in_line.each_index.min_by { |index|
        dx = in_line[index][0] - stop.dig("geometry", "coordinates")[0]
        dy = in_line[index][1] - stop.dig("geometry", "coordinates")[1]
        dx * dx + dy * dy
      }
    }
    assert_operator in_idxs[0], :<, in_idxs[1], "inbound 橫科 approach precedes the 舊莊 exit pole"
    assert_not Geojson::BusShapePatches.process_collection!(data)
  end

  test "紅5 outbound turns at 劍潭路／基河路 after 北藝中心 before the return tip" do
    turnaround = Geojson::BusShapePatches::HONG5_JIANTAN_TURNAROUND
    %w[taipei_hong5_2441bedf1c taipei_hong5_312257b87e].each do |route_id|
      line = [
        [ 121.5254186, 25.0853438 ],
        [ 121.5253923, 25.0852817 ],
        turnaround[:from].dup
      ]
      data = {
        "type" => "FeatureCollection",
        "properties" => { "id" => route_id },
        "features" => [ route(0, line) ]
      }

      assert Geojson::BusShapePatches.process_collection!(data), route_id

      patched = data["features"].first.dig("geometry", "coordinates")
      assert_equal line.first(2), patched.first(2)
      assert_equal turnaround[:from], patched[2]
      assert_equal turnaround[:path], patched[3, turnaround[:path].length]
      south = patched.any? { |point| point[1] < turnaround[:from][1] - 0.0004 }
      assert south, "turnaround should reach south of 北藝 tip toward 基河路 (#{route_id})"
      assert_not Geojson::BusShapePatches.process_collection!(data), route_id
    end
  end

  test "紅7 outbound turns south at 萬金路口 instead of overshooting 153弄" do
    patch = Geojson::BusShapePatches::PATCHES.fetch("taipei_hong7").first
    north_tip = [ 121.486318, 25.110536 ]
    line = [
      [ 121.49004, 25.10978 ],
      patch[:from].dup,
      north_tip.dup,
      patch[:to].dup,
      [ 121.48682, 25.1061 ]
    ]
    data = {
      "type" => "FeatureCollection",
      "properties" => { "id" => "taipei_hong7" },
      "features" => [ route(0, line) ]
    }

    assert Geojson::BusShapePatches.process_collection!(data)

    patched = data["features"].first.dig("geometry", "coordinates")
    assert_equal line.first, patched.first
    assert_equal patch[:from], patched[1]
    assert_equal patch[:path], patched[2, patch[:path].length]
    assert_equal patch[:to], patched[2 + patch[:path].length]
    assert_equal line.last, patched.last
    segment = patched[1..(2 + patch[:path].length)]
    assert segment.none? { |point| point[1] > 25.1094 }, "should not overshoot north of 萬金路口"
    wanjin = segment.any? { |point|
      Geojson::BusLoopCloser.meters_between(point, [ 121.4864995, 25.1093014 ]) < 15
    }
    assert wanjin, "patched path should pass 萬金路口"
    assert_not Geojson::BusShapePatches.process_collection!(data)
  end

  test "990 outbound leaves 捷運淡水站 along 中正東路 instead of a plaza chord" do
    patch = Geojson::BusShapePatches::PATCHES.fetch("new_taipei_990").first
    line = [
      [ 121.446112, 25.1678634 ],
      patch[:from].dup,
      patch[:to].dup,
      [ 121.4447898, 25.1690077 ]
    ]
    data = {
      "type" => "FeatureCollection",
      "properties" => { "id" => "new_taipei_990" },
      "features" => [ route(0, line) ]
    }

    assert Geojson::BusShapePatches.process_collection!(data)

    patched = data["features"].first.dig("geometry", "coordinates")
    assert_equal line.first, patched.first
    assert_equal patch[:from], patched[1]
    assert_equal patch[:path], patched[2, patch[:path].length]
    assert_equal patch[:to], patched[2 + patch[:path].length]
    assert_equal line.last, patched.last
    chord = Geojson::BusLoopCloser.meters_between(patch[:from], patch[:to])
    hops = ([ patch[:from] ] + patch[:path] + [ patch[:to] ]).each_cons(2).map { |a, b|
      Geojson::BusLoopCloser.meters_between(a, b)
    }
    assert_operator hops.max, :<, chord
    assert_not Geojson::BusShapePatches.process_collection!(data)
  end

  private

  def collection(*features)
    { "type" => "FeatureCollection", "properties" => { "id" => "test_route" }, "features" => features }
  end

  def route(direction, coordinates)
    {
      "type" => "Feature",
      "properties" => { "feature_type" => "route", "direction" => direction },
      "geometry" => { "type" => "LineString", "coordinates" => coordinates.map(&:dup) }
    }
  end

  def station(direction, name, point, platform = nil)
    properties = { "feature_type" => "station", "direction" => direction, "name" => name }
    properties["platform"] = platform if platform
    {
      "type" => "Feature",
      "properties" => properties,
      "geometry" => { "type" => "Point", "coordinates" => point.dup }
    }
  end

  def straight_router
    router = Object.new
    router.define_singleton_method(:route) { |from, to| [ from, to ] }
    router
  end
end
