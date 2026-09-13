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
    when %r{v2/Rail/THSR/DailyTimetable} then :thsr
    when %r{v2/Rail/Metro/Frequency/} then :metro_frequency
    when %r{v2/Rail/Metro/StationTimeTable/} then :metro_station_timetable
    else
      raise "unexpected path: #{path}"
    end

    payload = @fixtures.fetch(key)
    Transit::ResponseDecoder.list(payload)
  end
end

class FakeTraOdsClient
  def initialize(days:)
    @days = days
  end

  def fetch_daily_timetables(**)
    @days
  end
end

class TransitScheduleImporterTest < ActiveSupport::TestCase
  setup do
    Transit::CatalogSync.sync!
    @fixtures = {
      thsr: JSON.parse(file_fixture("tdx/thsr_daily_timetable.json").read),
      metro_frequency: JSON.parse(file_fixture("tdx/metro_frequency.json").read),
      metro_station_timetable: JSON.parse(file_fixture("tdx/metro_station_timetable.json").read)
    }
    @client = FakeTdxClient.new(@fixtures)
    @ods_payload = JSON.parse(file_fixture("ods/tra_daily_20260824.json").read)
    stations = JSON.parse(file_fixture("ods/stations.json").read).each_with_object({}) do |row, index|
      index[row["stationCode"]] = row["stationName"]
    end
    @ods_client = FakeTraOdsClient.new(
      days: [
        {
          date: Date.new(2026, 8, 24),
          trains: Transit::TraOdsClient.new.send(:normalize_trains, @ods_payload, stations)
        }
      ]
    )
  end

  test "imports TRA trips from ODS daily files with date calendars" do
    result = Transit::ScheduleImporter.new(client: @client, systems: %w[tra], ods_client: @ods_client).import!

    trip = ScheduleTrip.find_by!(schedule_dataset: result.dataset, train_number: "133")
    assert_equal "板橋", trip.destination_name
    assert_equal "本列車於板橋站後改為200次", trip.notes
    assert_equal 3, trip.trip_stop_times.count
    assert_equal "date_2026-08-24", trip.service_calendar.code
    refs = trip.ordered_stop_times.map(&:station_ref)
    assert_includes refs.first, "1000"
    assert_equal "1010", refs[1]
    assert_includes refs.last, "1020"
  end

  test "imports THSR daily timetable trips" do
    result = Transit::ScheduleImporter.new(client: @client, systems: %w[hsr], ods_client: @ods_client).import!

    trip = ScheduleTrip.find_by!(schedule_dataset: result.dataset, train_number: "0117")
    assert_equal "左營", trip.destination_name
    assert trip.trip_stop_times.exists?(station_ref: "02")
    assert trip.trip_stop_times.exists?(station_ref: "12")
    assert_match(/\Adate_/, trip.service_calendar.code)
  end

  test "stitches metro station boards into multi-stop trips" do
    result = Transit::ScheduleImporter.new(client: @client, systems: %w[metro], ods_client: @ods_client).import!

    assert_operator result.headways, :>=, 1
    trip = ScheduleTrip.joins(:transit_route).find_by!(transit_routes: { route_id: "bannan" }, train_number: "BL-0602")
    assert_operator trip.trip_stop_times.count, :>=, 2
  end

  test "replaces previous TDX dataset and keeps manual schedules active" do
    manual = ScheduleDataset.create!(name: "糖鐵時刻", source: "manual", active: true)
    demo = ScheduleDataset.create!(name: Transit::SampleScheduleSeeder::DATASET_NAME, source: "manual", active: true)

    first = Transit::ScheduleImporter.new(client: @client, systems: %w[hsr], ods_client: @ods_client).import!
    second = Transit::ScheduleImporter.new(client: @client, systems: %w[hsr], ods_client: @ods_client).import!

    assert second.dataset.active?
    refute ScheduleDataset.exists?(first.dataset.id)
    assert_equal 1, ScheduleDataset.tdx.count
    assert manual.reload.active?
    refute demo.reload.active?
  end
end

class TransitTraOdsClientTest < ActiveSupport::TestCase
  test "parses list page and daily JSON into normalized trains" do
    list_html = file_fixture("ods/schedule_list.html").read
    daily = file_fixture("ods/tra_daily_20260824.json").read
    stations = file_fixture("ods/stations.json").read

    http_get = lambda do |url|
      case url
      when Transit::TraOdsClient::LIST_URL then list_html
      when Transit::TraOdsClient::STATIONS_URL then stations
      when /exceptionDataResource/ then daily
      else
        raise "unexpected url #{url}"
      end
    end

    days = Transit::TraOdsClient.new(http_get: http_get).fetch_daily_timetables(from_date: Date.new(2026, 8, 24), days: 14, min_days: 7)
    assert_equal 7, days.length
    train = days.first[:trains].first
    assert_equal "133", train["TrainInfo"]["TrainNo"]
    assert_equal 3, train["StopTimes"].length
  end
end

class TransitMetroTripStitcherTest < ActiveSupport::TestCase
  test "groups boards with the same train number into one trip" do
    boards = [
      { route_id: 1, direction: "outbound", calendar_code: "weekday", train_number: "BL-1", destination_name: "頂埔", trip_type: "local", station_ref: "BL12", sequence: 12, departure_minutes: 362, arrival_time: Time.zone.parse("06:02"), departure_time: Time.zone.parse("06:02") },
      { route_id: 1, direction: "outbound", calendar_code: "weekday", train_number: "BL-1", destination_name: "頂埔", trip_type: "local", station_ref: "BL13", sequence: 13, departure_minutes: 364, arrival_time: Time.zone.parse("06:04"), departure_time: Time.zone.parse("06:04") }
    ]

    trips = Transit::MetroTripStitcher.new.stitch(boards)
    assert_equal 1, trips.length
    assert_equal "BL-1", trips.first.train_number
    assert_equal %w[BL12 BL13], trips.first.stops.map { |stop| stop[:station_ref] }
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
    assert_equal "02", @resolver.resolve_ref(system_id: "hsr", tdx_station_id: "1000")
    tra_ref = @resolver.resolve_ref(system_id: "tra", tdx_station_id: "1000")
    assert_includes tra_ref, "1000"
  end
end
