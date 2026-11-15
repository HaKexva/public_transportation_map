# frozen_string_literal: true

require "test_helper"

class Transit::ItineraryCompilerTest < ActiveSupport::TestCase
  test "ferry catalog covers every pier line with a matching stop count" do
    Geojson::FerryCatalog::FALLBACK_STATIONS_BY_SLUG.each_key do |slug|
      entry = Transit::FerryScheduleCatalog.fetch(slug)
      assert entry, slug
      stations = Geojson::FerryCatalog::FALLBACK_STATIONS_BY_SLUG[slug]
      Array(entry[:headways]).each do |band|
        assert_equal stations.length - 1, band[:ride].length, slug
      end
      Array(entry[:trips]).each do |trip|
        assert_equal stations.length, trip[:times].length, slug
      end
    end

    refute Transit::FerryScheduleCatalog.scheduled?("not_a_ferry")
  end

  test "builds timetable, headway, bus groups, ferry, and transfer links" do
    patterns = [
      {
        id: "tra:local",
        name: "區間車",
        mode: "rail",
        stops: [
          stop("rail:a", "甲站", 25.0, 121.50),
          stop("rail:b", "乙站", 25.03, 121.50)
        ],
        services: { "weekday" => { trips: [ [ 8 * 60, 8 * 60 + 20 ] ], headways: [] } }
      },
      {
        id: "metro:blue",
        name: "藍線",
        mode: "metro",
        stops: [
          stop("metro:c", "丙站", 25.04, 121.50),
          stop("metro:d", "丁站", 25.06, 121.50)
        ],
        services: { "weekday" => { trips: [], headways: [ { start: 6 * 60, end: 23 * 60, every: 6 } ] } }
      },
      {
        id: "bus:1:0",
        name: "1",
        mode: "bus",
        stops: [
          stop("bus:g1", "站牌群", 25.10, 121.40),
          stop("bus:g1", "站牌群", 25.10, 121.40),
          stop("bus:g2", "下一站", 25.11, 121.40)
        ],
        services: { "daily" => { trips: [ [ 9 * 60, 9 * 60, 9 * 60 + 15 ] ], headways: [] } }
      }
    ]
    patterns.concat(Transit::Itinerary::Compiler.ferry_patterns.select { |pattern| pattern[:id].start_with?("cijin_ferry") })

    graph = Transit::Itinerary::Compiler.build(
      patterns:,
      transfers: [ { from_key: "rail:b", to_key: "metro:c", minutes: 4 } ]
    )

    assert graph.stops.any? { |stop| stop["key"] == "bus:g1" }
    assert_equal 1, graph.stops.count { |stop| stop["key"] == "bus:g1" }
    bus = graph.routes.find { |route| route["id"] == "bus:1:0" }
    assert_equal 2, bus["patterns"].first["stops"].length
    assert_equal [ 9 * 60, 9 * 60 + 15 ], bus["patterns"].first["services"]["daily"]["trips"].first["times"]

    metro = graph.routes.find { |route| route["id"] == "metro:blue" }
    ride = metro["patterns"].first["services"]["weekday"]["headways"].first["ride"]
    assert_equal 1, ride.length
    assert ride.first.positive?

    cijin = graph.routes.select { |route| route["id"].start_with?("cijin_ferry") }
    assert_equal 2, cijin.length
    assert_equal [ 5 ], cijin.first["patterns"].first["services"]["daily"]["headways"].first["ride"]

    rail_b = graph.stops.index { |stop| stop["key"] == "rail:b" }
    metro_c = graph.stops.index { |stop| stop["key"] == "metro:c" }
    assert_includes graph.foot[rail_b], [ metro_c, 4 ]

    near = stop("near:a", "近甲", 25.0, 121.50)
    far = stop("near:b", "遠乙", 25.0 + (200.0 / 111_320), 121.50)
    distant = stop("near:c", "很遠", 25.0 + (5_000.0 / 111_320), 121.50)
    nearby = Transit::Itinerary::Compiler.build(patterns: [
      { id: "walk", name: "步", mode: "bus", stops: [ near, far ], services: { "daily" => { trips: [ [ 0, 10 ] ], headways: [] } } },
      { id: "far", name: "遠", mode: "bus", stops: [ distant, stop("near:d", "更遠", 25.2, 121.50) ], services: { "daily" => { trips: [ [ 0, 10 ] ], headways: [] } } }
    ])
    left = nearby.stops.index { |item| item["key"] == "near:a" }
    right = nearby.stops.index { |item| item["key"] == "near:b" }
    away = nearby.stops.index { |item| item["key"] == "near:c" }
    assert nearby.foot[left].any? { |target, minutes| target == right && minutes.between?(3, 6) }
    refute nearby.foot[left].any? { |target, _minutes| target == away }
  end

  test "reads a rail trip and a metro headway from schedule rows" do
    route = TransitRoute.create!(system_id: "tra", route_id: "itinerary_local", name: "測試區間", line_ref: "IL")
    dataset = ScheduleDataset.create!(name: "itinerary", source: "manual", active: true)
    calendar = ServiceCalendar.create!(schedule_dataset: dataset, code: "weekday", name: "平日")
    trip = ScheduleTrip.create!(
      schedule_dataset: dataset, transit_route: route, service_calendar: calendar,
      direction: "southbound", train_number: "1"
    )
    TripStopTime.create!(schedule_trip: trip, station_ref: "1000", stop_sequence: 1, departure_time: Time.zone.parse("08:00"))
    TripStopTime.create!(schedule_trip: trip, station_ref: "1010", stop_sequence: 2, arrival_time: Time.zone.parse("08:20"))
    coords = { [ "tra", "1000" ] => [ 25.047, 121.517 ], [ "tra", "1010" ] => [ 25.014, 121.463 ] }

    patterns = Transit::Itinerary::Compiler.patterns_from_schedule_trips([ trip ], coords:)
    assert_equal [ 8 * 60, 8 * 60 + 20 ], patterns.first[:services]["weekday"][:trips].first[:times]
    assert_equal "1", patterns.first[:services]["weekday"][:trips].first[:train]
    assert_equal "1000", patterns.first[:stops].first[:name]
    assert_includes patterns.first[:stops].first[:aliases], "itinerary_local:1000"

    metro = TransitRoute.create!(system_id: "taipei_metro", route_id: "itinerary_blue", name: "測試藍線", line_ref: "BL")
    TransitRouteStation.create!(transit_route: metro, station_ref: "BL1", name: "起", stop_sequence: 1, direction: "forward")
    TransitRouteStation.create!(transit_route: metro, station_ref: "BL2", name: "迄", stop_sequence: 2, direction: "forward")
    rule = HeadwayRule.create!(
      schedule_dataset: dataset, transit_route: metro, service_calendar: calendar,
      direction: "outbound", starts_at: Time.zone.parse("06:00"), ends_at: Time.zone.parse("23:00"),
      interval_seconds: 6 * 60
    )
    metro_coords = { [ "taipei_metro", "BL1" ] => [ 25.0, 121.5 ], [ "taipei_metro", "BL2" ] => [ 25.01, 121.5 ] }
    headways = Transit::Itinerary::Compiler.patterns_from_headway_rules([ rule ], coords: metro_coords)
    assert_equal 2, headways.length
    outbound = headways.find { |pattern| pattern[:id].end_with?(":outbound:headway") }
    inbound = headways.find { |pattern| pattern[:id].end_with?(":inbound:headway") }
    assert_equal "起", outbound[:stops].first[:name]
    assert_equal "迄", outbound[:stops].last[:name]
    assert_equal "迄", inbound[:stops].first[:name]
    assert_equal "起", inbound[:stops].last[:name]
    assert_equal 6, outbound[:services]["weekday"][:headways].first[:every]
    assert_equal "metro", outbound[:mode]
  end

  test "orders metro headway stops by line number and mirrors the missing direction" do
    dataset = ScheduleDataset.create!(name: "itinerary-order", source: "manual", active: true)
    calendar = ServiceCalendar.create!(schedule_dataset: dataset, code: "weekday", name: "平日")
    metro = TransitRoute.create!(system_id: "taipei_metro", route_id: "itinerary_bl_order", name: "板南線", line_ref: "BL")
    [
      [ "BL01", "頂埔", 1 ],
      [ "BL13", "善導寺", 2 ],
      [ "G12;BL11", "西門", 3 ],
      [ "R10;BL12", "台北車站", 4 ]
    ].each do |ref, name, sequence|
      TransitRouteStation.create!(
        transit_route: metro, station_ref: ref, name: name,
        stop_sequence: sequence, direction: "both"
      )
    end
    rule = HeadwayRule.create!(
      schedule_dataset: dataset, transit_route: metro, service_calendar: calendar,
      direction: "outbound", starts_at: Time.zone.parse("06:00"), ends_at: Time.zone.parse("23:00"),
      interval_seconds: 8 * 60
    )
    coords = {
      [ "taipei_metro", "BL01" ] => [ 24.96, 121.42 ],
      [ "taipei_metro", "BL13" ] => [ 25.04, 121.52 ],
      [ "taipei_metro", "G12;BL11" ] => [ 25.04, 121.51 ],
      [ "taipei_metro", "R10;BL12" ] => [ 25.05, 121.52 ]
    }

    patterns = Transit::Itinerary::Compiler.patterns_from_headway_rules([ rule ], coords:)
    outbound = patterns.find { |pattern| pattern[:id].include?(":outbound:headway") }
    inbound = patterns.find { |pattern| pattern[:id].include?(":inbound:headway") }

    assert_equal %w[頂埔 西門 台北車站 善導寺], outbound[:stops].map { |stop| stop[:name] }
    assert_equal %w[善導寺 台北車站 西門 頂埔], inbound[:stops].map { |stop| stop[:name] }
  end

  test "mirrors every headway band into the opposite direction" do
    dataset = ScheduleDataset.create!(name: "itinerary-bands", source: "manual", active: true)
    calendar = ServiceCalendar.create!(schedule_dataset: dataset, code: "weekday", name: "平日")
    metro = TransitRoute.create!(system_id: "taipei_metro", route_id: "itinerary_bl_bands", name: "測試", line_ref: "BL")
    TransitRouteStation.create!(transit_route: metro, station_ref: "BL01", name: "起", stop_sequence: 1, direction: "both")
    TransitRouteStation.create!(transit_route: metro, station_ref: "BL02", name: "迄", stop_sequence: 2, direction: "both")
    [ [ "06:00", "07:00" ], [ "17:00", "19:00" ] ].each do |starts, ends|
      HeadwayRule.create!(
        schedule_dataset: dataset, transit_route: metro, service_calendar: calendar,
        direction: "outbound", starts_at: Time.zone.parse(starts), ends_at: Time.zone.parse(ends),
        interval_seconds: 6 * 60
      )
    end
    coords = {
      [ "taipei_metro", "BL01" ] => [ 25.0, 121.5 ],
      [ "taipei_metro", "BL02" ] => [ 25.01, 121.5 ]
    }

    patterns = Transit::Itinerary::Compiler.patterns_from_headway_rules(HeadwayRule.where(transit_route: metro), coords:)
    inbound = patterns.select { |pattern| pattern[:id].include?(":inbound:headway") }
    bands = inbound.flat_map { |pattern| pattern[:services]["weekday"][:headways] }

    assert_equal 2, inbound.length
    assert_equal [ [ 6 * 60, 7 * 60 ], [ 17 * 60, 19 * 60 ] ], bands.map { |band| [ band[:start], band[:end] ] }.sort
  end

  test "collapses a bus stop group and keeps a headway when there is no timetable" do
    directory = {
      "A" => stop("bus:g1", "起站", 25.0, 121.5),
      "B" => stop("bus:g1", "起站", 25.0, 121.5),
      "C" => stop("bus:g2", "迄站", 25.01, 121.5)
    }
    weekday = Date::DAYNAMES.rotate.each_with_object({}) { |day, row| row[day] = %w[Saturday Sunday].include?(day) ? 0 : 1 }
    timed = Transit::Itinerary::Compiler.bus_patterns_for(
      city_id: "Taipei",
      route_name: "5",
      schedules: [ {
        "Direction" => 0,
        "Timetables" => [ {
          "ServiceDay" => weekday,
          "StopTimes" => [
            { "StopSequence" => 1, "StopUID" => "A", "DepartureTime" => "08:00" },
            { "StopSequence" => 2, "StopUID" => "B", "DepartureTime" => "08:01" },
            { "StopSequence" => 3, "StopUID" => "C", "DepartureTime" => "08:20" }
          ]
        } ],
        "Frequencys" => [ weekday.merge("StartTime" => "06:00", "EndTime" => "22:00", "MaxHeadwayMins" => 12).merge("ServiceDay" => weekday) ]
      } ],
      stops_by_uid: directory
    )
    assert_equal [ "bus:g1", "bus:g2" ], timed.first[:stops].map { |item| item[:key] }
    assert_equal [ 8 * 60, 8 * 60 + 20 ], timed.first[:services]["weekday"][:trips].first
    assert_empty timed.first[:services]["weekday"][:headways]

    frequency = Transit::Itinerary::Compiler.bus_patterns_for(
      city_id: "Taipei",
      route_name: "6",
      schedules: [ {
        "Direction" => 0,
        "Frequencys" => [ { "ServiceDay" => weekday, "StartTime" => "06:00", "EndTime" => "22:00", "MaxHeadwayMins" => 15 } ]
      } ],
      stops_by_uid: directory,
      sequence_uids: { 0 => %w[A C] }
    )
    assert_equal 15, frequency.first[:services]["weekday"][:headways].first[:every]
    assert_empty frequency.first[:services]["weekday"][:trips]

    origin_only = Transit::Itinerary::Compiler.bus_patterns_for(
      city_id: "Taipei",
      route_name: "294",
      schedules: [ {
        "Direction" => 0,
        "Timetables" => [ {
          "ServiceDay" => weekday,
          "StopTimes" => [
            { "StopSequence" => 1, "StopUID" => "A", "DepartureTime" => "08:00" }
          ]
        } ]
      } ],
      stops_by_uid: directory,
      sequence_uids: { 0 => %w[A C] }
    )
    assert_equal [ "bus:g1", "bus:g2" ], origin_only.first[:stops].map { |item| item[:key] }
    trip = origin_only.first[:services]["weekday"][:trips].first
    assert_equal 8 * 60, trip.first
    assert_operator trip.last, :>, trip.first
  end

  test "reads an out-of-station transfer by route and ref" do
    edges = Transit::Itinerary::Compiler.transfer_edges(
      [ { "kind" => "passage", "endpoints" => [ { "route_id" => "blue", "ref" => "BL12" }, { "route_id" => "red", "ref" => "R10" } ] } ],
      { "blue:BL12" => "rail:metro:BL12", "red:R10" => "rail:metro:R10" }
    )
    assert_equal({ from_key: "rail:metro:BL12", to_key: "rail:metro:R10", minutes: 4 }, edges.first)
  end

  def stop(key, name, lat, lon)
    { key:, name:, name_en: "", lat:, lon:, kind: "bus" }
  end
end
