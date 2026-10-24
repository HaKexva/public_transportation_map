# frozen_string_literal: true

require "test_helper"

class TransitBusRouteDetailsQueryTest < ActiveSupport::TestCase
  ROUTE = { "id" => "taipei_test_1", "ref" => "0東", "city_id" => "Taipei" }.freeze

  def run_query
    Transit::BusRouteDetailsQuery.new(route_id: ROUTE["id"], route: ROUTE.dup).call
  end

  def trip(time, days = %w[Monday])
    {
      "ServiceDay" => %w[Sunday Monday Tuesday Wednesday Thursday Friday Saturday].index_with { |day| days.include?(day) ? 1 : 0 },
      "StopTimes" => [ { "StopSequence" => 1, "DepartureTime" => time } ]
    }
  end

  test "builds hours, timetable headways, section fares and buffer zones" do
    Transit::BusTdxSnapshot.write_city!(
      "Taipei",
      schedules: [
        {
          "RouteUID" => "TPE10841", "RouteName" => { "Zh_tw" => "0東" }, "SubRouteName" => { "Zh_tw" => "0東" }, "Direction" => 0,
          "Timetables" => [ trip("06:00"), trip("06:20"), trip("07:00"), trip("09:00", %w[Sunday]) ]
        }
      ],
      fares: [
        {
          "RouteName" => { "Zh_tw" => "0東" }, "RouteID" => "10841", "SubRouteName" => "0東", "IsFreeBus" => 0,
          "SectionFares" => [
            {
              "BufferZones" => [
                { "Direction" => 0, "FareBufferZoneOrigin" => { "StopName" => "新益里" }, "FareBufferZoneDestination" => { "StopName" => "忠孝敦化路口" } }
              ],
              "Fares" => [
                { "TicketType" => 1, "FareClass" => 1, "Price" => 15 },
                { "TicketType" => 1, "FareClass" => 4, "Price" => 8 }
              ]
            }
          ]
        }
      ],
      routes: [
        {
          "RouteUID" => "TPE10841", "RouteName" => { "Zh_tw" => "0東" }, "BusRouteType" => 11,
          "DepartureStopNameZh" => "內湖", "DestinationStopNameZh" => "臺北車站",
          "TicketPriceDescriptionZh" => "兩段票",
          "SubRoutes" => [
            { "SubRouteName" => { "Zh_tw" => "0東" }, "Direction" => 0, "FirstBusTime" => "0600", "LastBusTime" => "2130" },
            { "SubRouteName" => { "Zh_tw" => "0東狗狗公車" }, "Direction" => 0, "FirstBusTime" => "1000", "LastBusTime" => "1500" }
          ]
        }
      ]
    )

    payload = run_query

    assert_equal "臺北車站", payload[:destination_stop]
    assert_equal [ { direction: 0, first: "06:00", last: "21:30" } ], payload[:service_hours]

    weekday = payload[:schedules].first[:weekday]
    assert_equal %w[06:00 06:20 07:00], weekday[:departures]
    assert_equal({ min: 20, max: 40, median: 40 }, weekday[:headway])
    assert_equal %w[09:00], payload[:schedules].first[:holiday][:departures]

    assert_equal "section", payload[:fare][:pricing]
    assert_equal [ { fare_class: "adult", price: 15 }, { fare_class: "senior", price: 8 } ], payload[:fare][:prices]
    assert_equal [ { direction: 0, from: "新益里", to: "忠孝敦化路口" } ], payload[:fare][:buffer_zones]
  end

  test "serves OD fares as an adult range" do
    Transit::BusTdxSnapshot.write_city!(
      "Taipei",
      schedules: [ { "RouteUID" => "TPE10841", "RouteName" => { "Zh_tw" => "0東" }, "Direction" => 0, "Timetables" => [ trip("06:00") ] } ],
      routes: [ { "RouteUID" => "TPE10841", "RouteName" => { "Zh_tw" => "0東" }, "DestinationStopNameZh" => "臺北車站" } ],
      fares: [
        {
          "RouteName" => { "Zh_tw" => "0東" },
          "ODFares" => [ 15, 42, 27 ].map { |price| { "Fares" => [ { "TicketType" => 1, "FareClass" => 1, "Price" => price } ] } }
        }
      ]
    )

    payload = run_query

    assert_equal "臺北車站", payload[:destination_stop]
    assert_equal [ 15, 42 ], payload[:fare][:adult_range]
    assert_equal %w[06:00], payload[:schedules].first[:weekday][:departures]
  end

  test "reports not_found when no timetable is stored" do
    assert_equal "not_found", run_query[:error]
  end

  test "adds the fleet seen on the route" do
    Transit::BusTdxSnapshot.write_city!("Taipei", schedules: [], routes: [ { "RouteUID" => "TPE1", "RouteName" => { "Zh_tw" => "0東" } } ], fares: [])
    BusVehicle.create!(plate: "EAL-0001", vehicle_class: 1, electric: true, low_floor: true, fetched_at: Time.current)
    BusRouteVehicleSighting.create!(route_id: ROUTE["id"], plate: "EAL-0001", first_seen_at: 1.day.ago, last_seen_at: Time.current)

    fleet = run_query[:fleet]

    assert_equal 1, fleet[:vehicle_count]
    assert_equal [ { vehicle_class: "large", power: "electric", low_floor: true, count: 1, share: 100 } ], fleet[:types]
  end
end
