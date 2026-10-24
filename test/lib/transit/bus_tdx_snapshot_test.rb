# frozen_string_literal: true

require "test_helper"

class TransitBusTdxSnapshotTest < ActiveSupport::TestCase
  def write(names, fetched_at: Time.current)
    Transit::BusTdxSnapshot.write_city!(
      "Taipei",
      schedules: names.map { |name| { "RouteUID" => "TPE#{name}", "RouteName" => { "Zh_tw" => name } } },
      routes: names.map { |name| { "RouteUID" => "TPE#{name}", "RouteName" => { "Zh_tw" => name } } },
      fares: [],
      fetched_at:
    )
  end

  test "round-trips one city's rows through the database" do
    write(%w[307 0東])

    snapshot = Transit::BusTdxSnapshot.read("Taipei", "307")
    assert_equal [ "TPE307" ], snapshot["schedules"].map { |row| row["RouteUID"] }
    assert_equal [ "TPE307" ], snapshot["routes"].map { |row| row["RouteUID"] }
    assert_equal [], snapshot["fares"]
    assert snapshot["fetched_at"].present?
    assert_nil Transit::BusTdxSnapshot.read("NewTaipei", "307")
  end

  test "drops routes the next refresh no longer lists" do
    write(%w[307 0東])
    write(%w[307])

    assert_equal %w[307], BusRouteTimetable.where(city_id: "Taipei").pluck(:route_name)
  end

  test "keeps serving old rows" do
    write(%w[307], fetched_at: 3.months.ago)

    assert Transit::BusTdxSnapshot.read("Taipei", "307")
  end

  test "imports the old snapshot files" do
    root = Pathname(Dir.mktmpdir)
    root.join("Keelung").mkpath
    root.join("Keelung/abc.json").write(JSON.generate(
      name: "101", fetched_at: "2026-10-01T04:30:00+08:00",
      schedules: [ { "RouteUID" => "KEE101" } ], routes: [], fares: []
    ))
    root.join("Keelung/bad.json").write("{")

    assert_equal 1, Transit::BusTdxSnapshot.import_files!(root:)
    assert_equal [ "KEE101" ], Transit::BusTdxSnapshot.read("Keelung", "101")["schedules"].map { |row| row["RouteUID"] }
  ensure
    FileUtils.rm_rf(root) if root
  end
end
