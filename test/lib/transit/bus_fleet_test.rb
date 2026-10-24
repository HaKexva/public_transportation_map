# frozen_string_literal: true

require "test_helper"

class TransitBusFleetTest < ActiveSupport::TestCase
  setup do
    Transit::BusVehicleModels.entries = [
      { "model" => "成運 MB120NSE", "operator_id" => "100", "plates" => [ "EAL-" ] },
      { "model" => "華德 RAC-500", "plates" => [ "-U3" ] }
    ]
  end

  teardown do
    Transit::BusVehicleModels.entries = nil
  end

  def vehicle(plate, operator_id: "100", **attrs)
    BusVehicle.create!(plate:, operator_id:, vehicle_class: 1, fetched_at: Time.current, **attrs)
  end

  test "parses the 大臺北 BusVehicleList XML" do
    xml = <<~XML
      <BusVehicleList xmlns="https://ptx.transportdata.tw/standard/schema/"><Vehicles>
        <Vehicle><PlateNumb>EAL-0001</PlateNumb><OperatorID>100</OperatorID><VehicleClass>1</VehicleClass><IsElectric>1</IsElectric><IsLowFloor>1</IsLowFloor></Vehicle>
      </Vehicles></BusVehicleList>
    XML

    Transit::BusFleet.store_vehicles!("Taipei", Transit::BusFleet.parse_vehicle_xml(xml))

    bus = BusVehicle.find_by!(plate: "EAL-0001")
    assert_equal [ "Taipei", "100", 1, true, true, false ], [ bus.city_id, bus.operator_id, bus.vehicle_class, bus.electric, bus.low_floor, bus.hybrid ]
  end

  test "maps live-feed SubRouteIDs to app routes and counts repeat sightings" do
    index = { "157462" => "taipei_307" }

    Transit::BusFleet.record_sightings!(index, [ [ "157462", "EAL-0001" ], [ "0", "EAL-0002" ] ], seen_at: 1.hour.ago)
    Transit::BusFleet.record_sightings!(index, [ [ "157462", "EAL-0001" ] ])

    sighting = BusRouteVehicleSighting.sole
    assert_equal [ "taipei_307", "EAL-0001", 2 ], [ sighting.route_id, sighting.plate, sighting.sightings ]
    assert sighting.last_seen_at > sighting.first_seen_at
  end

  test "summarises common types and models weighted by sightings" do
    vehicle("EAL-0001", electric: true, low_floor: true)
    vehicle("EAL-0002", electric: true, low_floor: true)
    vehicle("845-U3", operator_id: "200")
    vehicle("KKA-0001", vehicle_class: 3)
    now = Time.current
    { "EAL-0001" => 5, "EAL-0002" => 3, "845-U3" => 2, "KKA-0001" => 0 }.each do |plate, seen|
      next if seen.zero?

      BusRouteVehicleSighting.create!(route_id: "taipei_307", plate:, sightings: seen, first_seen_at: now, last_seen_at: now)
    end
    BusRouteVehicleSighting.create!(route_id: "taipei_307", plate: "KKA-0001", sightings: 50, first_seen_at: 3.months.ago, last_seen_at: 2.months.ago)

    summary = Transit::BusFleet.summary("taipei_307")

    assert_equal 3, summary[:vehicle_count]
    assert_equal [
      { vehicle_class: "large", power: "electric", low_floor: true, count: 2, share: 80 },
      { vehicle_class: "large", count: 1, share: 20 }
    ], summary[:types]
    assert_equal [ { name: "成運 MB120NSE", count: 2, share: 80 }, { name: "華德 RAC-500", count: 1, share: 20 } ], summary[:models]
  end

  test "has no summary before any bus is seen" do
    assert_nil Transit::BusFleet.summary("taipei_307")
  end
end
