# frozen_string_literal: true

require "test_helper"

class GeojsonBusTerminusLinesTest < ActiveSupport::TestCase
  test "795 outbound trips and the shared return become 十分 and 平溪" do
    root = Pathname.new(Dir.mktmpdir("terminus"))
    dir = root.join("taipei_new_taipei_bus/700-799")
    FileUtils.mkdir_p(dir)
    write_route(dir, "out-shifen", "795往十分寮(台灣好行-木柵平溪線)", [ [ 121.57, 25.00 ], [ 121.70, 25.03 ], [ 121.74, 25.03 ] ], %w[動物園 平溪 十分遊客中心])
    write_route(dir, "out-pingxi", "795往平溪(台灣好行-木柵平溪線)", [ [ 121.57, 25.00 ], [ 121.70, 25.03 ] ], %w[動物園 平溪])
    write_route(dir, "back", "795往木柵(台灣好行-木柵平溪線)", [ [ 121.74, 25.03 ], [ 121.72, 25.03 ], [ 121.70, 25.03 ], [ 121.57, 25.00 ] ], %w[十分遊客中心 十分寮 平溪 動物園])

    written = Geojson::BusTerminusLines.apply!(bus_root: root, city_id: "NewTaipei")

    assert_equal 2, written.size
    assert_empty Dir[dir.join("*往*.geojson")]
    shifen = JSON.parse(File.read(dir.join("new_taipei_795_#{Digest::SHA1.hexdigest("十分")[0, 10]}.geojson")))
    pingxi = JSON.parse(File.read(dir.join("new_taipei_795_#{Digest::SHA1.hexdigest("平溪")[0, 10]}.geojson")))

    assert_equal "795（十分）", shifen.dig("properties", "name")
    assert_equal "795 (Shifen)", shifen.dig("properties", "name_en")
    assert_equal "795", shifen.dig("properties", "ref")
    assert_equal "795往十分寮(台灣好行-木柵平溪線)", shifen.dig("properties", "tdx_ref")
    assert_equal %w[十分遊客中心 十分寮 平溪 動物園], stop_names(shifen, 1)
    assert_equal %w[平溪 動物園], stop_names(pingxi, 1)
    inbound = pingxi["features"].find { |feature| feature.dig("properties", "direction") == 1 && feature.dig("geometry", "type") == "LineString" }
    assert_equal [ 121.70, 25.03 ], inbound.dig("geometry", "coordinates").first
  ensure
    FileUtils.remove_entry(root) if root
  end

  test "return trips follow the outbound order onto 十分 and 平溪" do
    week = %w[Monday Tuesday Wednesday Thursday Friday]
    weekend = %w[Saturday Sunday]
    shifen_out = %w[05:00 05:40].map { |time| trip(time, week) } + [ trip("09:40", weekend) ]
    pingxi_out = [ trip("04:50", week), trip("06:10", week + weekend) ]
    returns = [ trip("06:00", week), trip("06:20", week), trip("06:50", week), trip("07:20", week + weekend), trip("11:20", weekend) ]

    assigned = Geojson::BusTerminusLines.assign_return_trips(
      { "十分" => shifen_out, "平溪" => pingxi_out },
      returns
    )

    assert_equal %w[06:20 06:50 11:20], clocks(assigned["十分"])
    assert_equal %w[06:00 07:20], clocks(assigned["平溪"])
    weekend_shifen = assigned["十分"].find { |row| row["StopTimes"].first["DepartureTime"] == "11:20" }
    assert_equal 0, weekend_shifen.dig("ServiceDay", "Monday")
    assert_equal 1, weekend_shifen.dig("ServiceDay", "Saturday")
  end

  test "route details show the paired return on direction 1" do
    week = %w[Monday Tuesday Wednesday Thursday Friday]
    reads = {
      "795往十分寮(台灣好行-木柵平溪線)" => snapshot("795往十分寮", [ trip("05:00", week) ], "木柵", "十分寮"),
      "795往平溪(台灣好行-木柵平溪線)" => snapshot("795往平溪", [ trip("04:50", week) ], "木柵", "平溪"),
      "795往木柵(台灣好行-木柵平溪線)" => snapshot("795往木柵", [ trip("06:00", week), trip("06:20", week) ], "十分寮、平溪", "木柵")
    }
    route = {
      "id" => "new_taipei_795_#{Digest::SHA1.hexdigest("十分")[0, 10]}", "ref" => "795", "via" => "十分",
      "name" => "795（十分）", "city_id" => "NewTaipei"
    }
    payload = with_snapshots(reads) {
      Transit::BusRouteDetailsQuery.new(route_id: route["id"], route:).call
    }

    assert_equal "十分寮", payload[:destination_stop]
    assert_equal [ 0, 1 ], payload[:schedules].map { |row| row[:direction] }
    assert_equal %w[05:00], payload[:schedules][0][:weekday][:departures]
    assert_equal %w[06:20], payload[:schedules][1][:weekday][:departures]
    assert_equal({ direction: 1, first: "06:20", last: "06:20" }, payload[:service_hours].find { |row| row[:direction] == 1 })
  end

  module TerminusSnapshotFixture
    def read(city, name)
      fixture = Thread.current[:terminus_reads]
      return super unless fixture

      fixture[name] if city.to_s == "NewTaipei"
    end
  end
  Transit::BusTdxSnapshot.singleton_class.prepend(TerminusSnapshotFixture)

  def with_snapshots(reads)
    Thread.current[:terminus_reads] = reads
    yield
  ensure
    Thread.current[:terminus_reads] = nil
  end

  def trip(time, days)
    {
      "ServiceDay" => %w[Sunday Monday Tuesday Wednesday Thursday Friday Saturday].index_with { |day| days.include?(day) ? 1 : 0 },
      "StopTimes" => [ { "StopSequence" => 1, "DepartureTime" => time } ]
    }
  end

  def clocks(trips)
    trips.map { |row| row["StopTimes"].first["DepartureTime"] }.sort
  end

  def snapshot(name, trips, departure, destination)
    {
      "schedules" => [ { "RouteName" => { "Zh_tw" => name }, "SubRouteName" => { "Zh_tw" => name }, "Direction" => 0, "Timetables" => trips } ],
      "routes" => [ {
        "RouteName" => { "Zh_tw" => name }, "DepartureStopNameZh" => departure, "DestinationStopNameZh" => destination,
        "SubRoutes" => [ { "SubRouteName" => { "Zh_tw" => name }, "Direction" => 0, "FirstBusTime" => "0500", "LastBusTime" => "1910" } ]
      } ],
      "fares" => []
    }
  end

  def write_route(dir, slug, name, line, stops)
    features = [ {
      "type" => "Feature",
      "properties" => { "feature_type" => "route", "name" => name, "ref" => name, "direction" => 0 },
      "geometry" => { "type" => "LineString", "coordinates" => line }
    } ]
    stops.each_with_index do |stop, index|
      features << {
        "type" => "Feature",
        "properties" => { "feature_type" => "station", "name" => stop, "direction" => 0 },
        "geometry" => { "type" => "Point", "coordinates" => line[index] || line.last }
      }
    end
    File.write(dir.join("#{slug}.geojson"), JSON.generate(
      "type" => "FeatureCollection",
      "name" => name,
      "properties" => { "id" => slug, "name" => name, "ref" => name, "city_id" => "NewTaipei", "daily_trips" => 1 },
      "features" => features
    ))
  end

  def stop_names(data, direction)
    data["features"].select { |feature|
      feature.dig("geometry", "type") == "Point" && feature.dig("properties", "direction") == direction
    }.map { |feature| feature.dig("properties", "name") }
  end
end
