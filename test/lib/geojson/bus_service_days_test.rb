# frozen_string_literal: true

require "test_helper"

class GeojsonBusServiceDaysTest < ActiveSupport::TestCase
  WEEKDAYS = { "Monday" => 1, "Tuesday" => 1, "Wednesday" => 1, "Thursday" => 1, "Friday" => 1 }.freeze

  test "counts weekday trips in the busier direction from timetables and headway bands" do
    trip = ->(time, days = WEEKDAYS) { { "ServiceDay" => days, "StopTimes" => [ { "DepartureTime" => time } ] } }
    rows = [
      { "Direction" => 0, "Timetables" => [ trip.call("06:00"), trip.call("06:30"), trip.call("09:00", { "Saturday" => 1 }) ] },
      { "Direction" => 1, "Timetables" => [ trip.call("06:10") ],
        "Frequencys" => [ { "ServiceDay" => WEEKDAYS, "StartTime" => "07:00", "EndTime" => "09:00", "MinHeadwayMins" => 10, "MaxHeadwayMins" => 20 } ] }
    ]

    assert_equal 9, Geojson::BusServiceDays.daily_trips(rows)
    assert_nil Geojson::BusServiceDays.daily_trips([])
  end

  test "picks the timetable rows of a 本線 or 延駛 variant" do
    rows = [ { "SubRouteName" => { "Zh_tw" => "237不經政大校區" } }, { "SubRouteName" => { "Zh_tw" => "237經政大校區" } } ]
    own = ->(name, via) { Geojson::BusServiceDays.own_rows(rows, ref: "237", name:, via:).map { |row| row.dig("SubRouteName", "Zh_tw") } }

    assert_equal [ "237不經政大校區" ], own.("237（本線）", "本線")
    assert_equal [ "237經政大校區" ], own.("237（延駛政大校區）", "延駛政大校區")
  end

  test "flags a weekday-only route as suspended at weekends and holidays" do
    rows = [ { "Timetables" => [ { "ServiceDay" => WEEKDAYS.merge("Saturday" => 0, "Sunday" => 0, "NationalHolidays" => 0) } ] } ]
    assert_equal %w[saturday sunday holiday], Geojson::BusServiceDays.off_days(rows)
  end

  test "flags only the days with no trip in any timetable or frequency band" do
    rows = [
      { "Frequencys" => [ { "ServiceDay" => WEEKDAYS.merge("Saturday" => 0, "Sunday" => 0) } ] },
      { "Timetables" => [ { "ServiceDay" => { "Saturday" => 1, "Sunday" => 0 } } ] }
    ]
    assert_equal %w[sunday], Geojson::BusServiceDays.off_days(rows)
  end

  test "flags nothing for daily, weekend-only or day-less schedules" do
    daily = [ { "Timetables" => [ { "ServiceDay" => WEEKDAYS.merge("Saturday" => 1, "Sunday" => 1) } ] } ]
    weekend_only = [ { "Timetables" => [ { "ServiceDay" => { "Monday" => 0, "Saturday" => 1, "Sunday" => 1 } } ] } ]
    no_days = [ { "Frequencys" => [ { "StartTime" => "06:00" } ] } ]

    assert_empty Geojson::BusServiceDays.off_days(daily)
    assert_empty Geojson::BusServiceDays.off_days(weekend_only)
    assert_empty Geojson::BusServiceDays.off_days(no_days)
  end

  def trips(*times)
    [ { "Timetables" => times.map { |time| { "StopTimes" => [ { "DepartureTime" => time } ] } } } ]
  end

  test "labels a variant that only runs after the main route's last bus" do
    window = Geojson::BusServiceDays.service_window(trips("22:30"), trips("05:30", "21:30"))

    assert_equal({ "after" => "22:30" }, window)
    assert_equal "216（22:30後不繞駛榮總院區）", Geojson::BusServiceDays.display_name("216（不繞駛榮總院區）", window)
    assert_equal "5（06:00前）", Geojson::BusServiceDays.display_name("5", { "before" => "06:00" })
  end

  test "no label when the variant runs alongside the main route" do
    assert_nil Geojson::BusServiceDays.service_window(trips("07:00", "17:00"), trips("05:30", "21:30"))
    assert_equal "216", Geojson::BusServiceDays.display_name("216", nil)
  end

  test "applies the window to the variant file only when TDX has the plain route too" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "taipei_216_x.geojson")
      File.write(path, JSON.generate("properties" => { "ref" => "216", "name" => "216（不繞駛榮總院區）" }, "features" => []))
      city = Geojson::BusCatalog.find("Taipei")
      rows = [
        { "SubRouteName" => { "Zh_tw" => "216" } }.merge(trips("05:30", "21:30").first),
        { "SubRouteName" => { "Zh_tw" => "216不繞駛榮總院區" } }.merge(trips("22:30").first)
      ]

      assert Geojson::BusServiceDays.apply!(path, { "216" => rows }, city)
      assert_equal({ "after" => "22:30" }, JSON.parse(File.read(path)).dig("properties", "service_window"))

      File.write(path, JSON.generate("properties" => { "ref" => "8129", "name" => "8129（豐源）" }, "features" => []))
      Geojson::BusServiceDays.apply!(path, { "8129" => [ { "SubRouteName" => { "Zh_tw" => "8129豐源" } }.merge(trips("20:55").first) ] }, city)
      assert_nil JSON.parse(File.read(path)).dig("properties", "service_window")
    end
  end
end
