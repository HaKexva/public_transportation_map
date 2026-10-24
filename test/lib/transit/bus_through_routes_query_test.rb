# frozen_string_literal: true

require "test_helper"

class Transit::BusThroughRoutesQueryTest < ActiveSupport::TestCase
  setup do
    @root = Rails.root.join("tmp/bus_through_routes_#{name}")
    FileUtils.rm_rf(@root)
    FileUtils.mkdir_p(@root.join("keelung_bus"))
    index = {
      "stations" => {
        "KLS" => [ { "id" => "keelung_101", "ref" => "101", "name" => "101", "color" => "#123" } ]
      },
      "clusters" => {
        "25.1280|121.7400|海洋廣場" => [
          { "id" => "keelung_103", "ref" => "103", "name" => "103", "color" => "#456" }
        ]
      }
    }
    File.write(@root.join("keelung_bus/_stop_routes.json"), JSON.pretty_generate(index))
  end

  teardown do
    FileUtils.rm_rf(@root)
  end

  test "matches by station id" do
    result = Transit::BusThroughRoutesQuery.new(city_id: "Keelung", station_id: "KLS", bus_root: @root).call
    assert_nil result.error
    assert_equal [ "keelung_101" ], result.routes.map { |row| row["id"] }
  end

  test "matches nearby cluster by name" do
    result = Transit::BusThroughRoutesQuery.new(
      city_id: "Keelung",
      name: "海洋廣場",
      lat: 25.1281,
      lon: 121.7401,
      bus_root: @root
    ).call
    assert_equal [ "keelung_103" ], result.routes.map { |row| row["id"] }
  end

  test "lists nearby same-name stop groups with the clicked one first" do
    index = JSON.parse(File.read(@root.join("keelung_bus/_stop_routes.json")))
    index["stations"]["KLN"] = [ { "id" => "keelung_102", "ref" => "102" } ]
    index["groups"] = {
      "KLS" => { "name" => "海洋廣場", "lat" => 25.1280, "lon" => 121.7400, "stops" => [ "KEE1" ] },
      "KLN" => { "name" => "海洋廣場", "lat" => 25.1284, "lon" => 121.7400, "stops" => [ "KEE2", "KEE3" ] },
      "KLF" => { "name" => "海洋廣場", "lat" => 25.1400, "lon" => 121.7400, "stops" => [ "KEE9" ] },
      "KLX" => { "name" => "其他站", "lat" => 25.1281, "lon" => 121.7400, "stops" => [ "KEE5" ] }
    }
    File.write(@root.join("keelung_bus/_stop_routes.json"), JSON.generate(index))

    result = Transit::BusThroughRoutesQuery.new(
      city_id: "Keelung", station_id: "KLS", name: "海洋廣場", lat: 25.1280, lon: 121.7400, bus_root: @root
    ).call

    assert_equal [ "KLS", "KLX", "KLN" ], result.groups.map { |group| group[:id] }
    assert result.groups.first[:current]
    north = result.groups.last
    assert_in_delta 45, north[:distance_m], 2
    assert_equal 0, north[:bearing]
    assert_equal [ "KEE2", "KEE3" ], north[:stop_uids]
    assert_equal [ "keelung_102" ], north[:routes].map { |row| row["id"] }
  end

  test "picks the clicked platform of a terminal" do
    index = JSON.parse(File.read(@root.join("keelung_bus/_stop_routes.json")))
    index["stations"]["BQ@第一月台"] = [ { "id" => "keelung_307", "ref" => "307" } ]
    index["stations"]["BQ@第四月台"] = [ { "id" => "keelung_920", "ref" => "920" } ]
    index["groups"] = {
      "BQ@第一月台" => { "name" => "新北板橋公車站", "platform" => "第一月台", "platform_en" => "Platform 1", "lat" => 25.0128, "lon" => 121.4625, "stops" => [ "P1" ] },
      "BQ@第四月台" => { "name" => "新北板橋公車站", "platform" => "第四月台", "platform_en" => "Platform 4", "lat" => 25.0128, "lon" => 121.4622, "stops" => [ "P4" ] }
    }
    File.write(@root.join("keelung_bus/_stop_routes.json"), JSON.generate(index))

    result = Transit::BusThroughRoutesQuery.new(
      city_id: "Keelung", station_id: "BQ", platform: "第四月台", name: "新北板橋公車站", lat: 25.0128, lon: 121.4622, bus_root: @root
    ).call

    assert_equal [ "keelung_920" ], result.routes.map { |row| row["id"] }
    assert_equal [ "BQ@第四月台", "BQ@第一月台" ], result.groups.map { |group| group[:id] }
    assert_equal [ "第四月台", "第一月台" ], result.groups.map { |group| group[:platform] }
    assert result.groups.first[:current]
  end

  test "treats differently named stations of one place as one hub" do
    assert Transit::BusThroughRoutesQuery.same_hub?("新北板橋公車站", "板橋車站(文化路)")
    assert Transit::BusThroughRoutesQuery.same_hub?("板橋轉運站", "板橋外站")
    assert Transit::BusThroughRoutesQuery.same_hub?("臺北車站(忠孝)", "台北轉運站")
    refute Transit::BusThroughRoutesQuery.same_hub?("新北市政府(新府路)", "板橋車站(文化路)")
    refute Transit::BusThroughRoutesQuery.same_hub?("臺北車站(忠孝)", "板橋車站(文化路)")
  end

  test "lists hub stops with other bracketed streets and intercity stops nearby" do
    index = JSON.parse(File.read(@root.join("keelung_bus/_stop_routes.json")))
    index["groups"] = {
      "A" => { "name" => "臺北車站(忠孝)", "lat" => 25.0460, "lon" => 121.5170, "stops" => [ "T1" ] },
      "B" => { "name" => "台北車站(鄭州)", "lat" => 25.0500, "lon" => 121.5170, "stops" => [ "T2" ] },
      "C" => { "name" => "臺北車站(公園)", "lat" => 25.0600, "lon" => 121.5170, "stops" => [ "T3" ] },
      "D" => { "name" => "北門", "lat" => 25.0490, "lon" => 121.5170, "stops" => [ "T4" ] }
    }
    File.write(@root.join("keelung_bus/_stop_routes.json"), JSON.generate(index))
    FileUtils.mkdir_p(@root.join("intercity_bus"))
    File.write(@root.join("intercity_bus/_stop_routes.json"), JSON.generate(
      "stations" => { "I" => [ { "id" => "intercity_1815" } ] },
      "groups" => { "I" => { "name" => "臺北轉運站", "lat" => 25.0470, "lon" => 121.5170, "stops" => [ "X1" ] } }
    ))

    result = Transit::BusThroughRoutesQuery.new(
      city_id: "Keelung", station_id: "A", name: "臺北車站(忠孝)", lat: 25.0460, lon: 121.5170, bus_root: @root
    ).call

    assert_equal [ "A", "intercity_bus:I", "B" ], result.groups.map { |group| group[:id] }
    assert_equal [ "intercity_1815" ], result.groups[1][:routes].map { |row| row["id"] }
  end
end
