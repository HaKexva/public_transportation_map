# frozen_string_literal: true

require "test_helper"

class FakeTdxClient
  def configured?
    true
  end

  def initialize(fixtures)
    @fixtures = fixtures
  end

  def fetch_all(path, query: {}, page_size: 1_000)
    key = case path
    when %r{v3/Rail/TRA/GeneralTrainTimetable} then :tra
    when %r{v2/Rail/THSR/GeneralTimetable} then :thsr
    when %r{v2/Rail/Metro/Frequency/} then :metro_frequency
    when %r{v2/Rail/Metro/StationTimeTable/} then :metro_station_timetable
    else
      raise "unexpected path: #{path}"
    end

    payload = @fixtures.fetch(key)
    Transit::ResponseDecoder.list(payload)
  end
end

class TransitScheduleImporterTest < ActiveSupport::TestCase
  setup do
    Transit::CatalogSync.sync!
    @fixtures = {
      tra: JSON.parse(file_fixture("tdx/tra_general_timetable.json").read),
      thsr: JSON.parse(file_fixture("tdx/thsr_general_timetable.json").read),
      metro_frequency: JSON.parse(file_fixture("tdx/metro_frequency.json").read),
      metro_station_timetable: JSON.parse(file_fixture("tdx/metro_station_timetable.json").read)
    }
    @client = FakeTdxClient.new(@fixtures)
  end

  test "imports TRA trips with train numbers and stop times" do
    result = Transit::ScheduleImporter.new(client: @client, systems: %w[tra]).import!

    trip = ScheduleTrip.find_by!(schedule_dataset: result.dataset, train_number: "133")
    assert_equal "高雄", trip.destination_name
    assert_equal 3, trip.trip_stop_times.count
    refs = trip.ordered_stop_times.map(&:station_ref)
    assert_includes refs.first, "1000"
    assert_equal "1010", refs[1]
    assert_includes refs.last, "1020"
  end

  test "imports THSR trips with train numbers" do
    result = Transit::ScheduleImporter.new(client: @client, systems: %w[hsr]).import!

    trip = ScheduleTrip.find_by!(schedule_dataset: result.dataset, train_number: "0117")
    assert_equal "左營", trip.destination_name
    assert trip.trip_stop_times.exists?(station_ref: "02;1000;R10;BL12")
    assert trip.trip_stop_times.exists?(station_ref: "12;4340;R16")
  end

  test "imports metro headways and station departures" do
    result = Transit::ScheduleImporter.new(client: @client, systems: %w[metro]).import!

    assert_operator result.headways, :>=, 1
    assert ScheduleTrip.joins(:transit_route).where(transit_routes: { route_id: "bannan" }).exists?
  end
end

class TransitServiceDayMapperTest < ActiveSupport::TestCase
  test "maps weekday service patterns" do
    service_day = {
      "Monday" => 1, "Tuesday" => 1, "Wednesday" => 1, "Thursday" => 1, "Friday" => 1,
      "Saturday" => 0, "Sunday" => 0, "NationalHolidays" => 0
    }

    assert_equal %w[weekday], Transit::ServiceDayMapper.calendar_codes(service_day)
    assert Transit::ServiceDayMapper.weekday?(service_day)
  end
end

class TransitStationRefResolverTest < ActiveSupport::TestCase
  setup do
    Transit::CatalogSync.sync!
    @resolver = Transit::StationRefResolver.new
  end

  test "resolves HSR and TRA station ids" do
    assert_equal "02;1000;R10;BL12", @resolver.resolve_ref(system_id: "hsr", tdx_station_id: "1000")
    tra_ref = @resolver.resolve_ref(system_id: "tra", tdx_station_id: "1000")
    assert_includes tra_ref, "1000"
  end
end
