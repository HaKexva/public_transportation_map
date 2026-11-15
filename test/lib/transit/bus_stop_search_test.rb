# frozen_string_literal: true

require "test_helper"

class TransitBusStopSearchTest < ActiveSupport::TestCase
  setup do
    @root = Rails.root.join("tmp/bus_stop_search_#{SecureRandom.hex(4)}")
    FileUtils.mkdir_p(@root.join("keelung_bus"))
    FileUtils.mkdir_p(@root.join("taipei_new_taipei_bus"))
    write_index("keelung_bus", {
      "KEE1" => group("基隆車站", "Keelung Station", 25.1318, 121.7394, stops: [ "KEE100" ], road: "忠一路", toward: "海洋廣場"),
      "KEE9" => group("港口", "Port", 25.14, 121.75, stops: [ "KEE900" ], toward: "基隆車站"),
      "25.1000|121.7500|暖暖" => group("暖暖", "Nuannuan", 25.1, 121.75, stops: [ "KEE200" ], road: "暖暖街")
    })
    write_index("taipei_new_taipei_bus", {
      "TPE1" => group("臺北車站", "Taipei Main Station", 25.0478, 121.517, stops: [ "TPE1" ], road: "忠孝西路"),
      "NWT1" => group("板橋公車站", "Banqiao Bus Station", 25.014, 121.463, stops: [ "NWT1", "TPE9" ], platform: "第一月台"),
      "TPE2@第四月台" => group("新北板橋公車站", nil, 25.0128, 121.4622, stops: [ "TPE2" ], platform: "第四月台", platform_en: "Platform 4")
    })
    Geojson::BusStopSearchIndex.write!(bus_root: @root)
    Transit::BusStopSearch.reset_cache!
  end

  teardown do
    Transit::BusStopSearch.reset_cache!
    FileUtils.rm_rf(@root)
  end

  test "ranks exact and prefix names ahead of looser matches" do
    names = search("基隆").map { |stop| stop["name"] }

    assert_equal "基隆車站", names.first
    assert_not_includes names, "暖暖"
  end

  test "skips stops that only head toward the queried name" do
    assert_equal [ "基隆車站" ], search("基隆車站").map { |stop| stop["name"] }
  end

  test "treats 台 and 臺 as the same" do
    names = search("台北車站").map { |stop| stop["name"] }

    assert_equal [ "臺北車站" ], names
  end

  test "matches a stop by the street it stands on" do
    names = search("暖暖街").map { |stop| stop["name"] }

    assert_equal [ "暖暖" ], names
  end

  test "limits a shared folder to the requested city" do
    taipei = search("板橋", city_id: "Taipei").map { |stop| stop["name"] }
    new_taipei = search("板橋", city_id: "NewTaipei").map { |stop| stop["name"] }

    assert_includes taipei, "新北板橋公車站"
    assert_includes taipei, "板橋公車站"
    assert_equal [ "板橋公車站" ], new_taipei
  end

  test "keeps both cities when a pole has both stop ids" do
    stop = search("板橋公車站").first

    assert_equal "NewTaipei", stop["city_id"]
    assert_equal %w[NewTaipei Taipei], stop["city_ids"]
  end

  test "ignores queries that are too short" do
    assert_empty search("站")
    assert_empty search("ke")
  end

  test "exposes the station id behind a platform key" do
    stop = search("新北板橋").first

    assert_equal "TPE2", stop["station_id"]
    assert_equal "第四月台", stop["platform"]
    assert_equal "TPE2@第四月台", stop["group_id"]
  end

  private

  def search(query, city_id: nil)
    Transit::BusStopSearch.new(query: query, city_id: city_id, bus_root: @root).call
  end

  def write_index(subdir, groups)
    File.write(@root.join(subdir, "_stop_routes.json"), JSON.generate("groups" => groups))
  end

  def group(name, name_en, lat, lon, stops:, road: nil, toward: nil, platform: nil, platform_en: nil)
    {
      "name" => name,
      "name_en" => name_en,
      "lat" => lat,
      "lon" => lon,
      "stops" => stops,
      "road" => road,
      "toward" => toward,
      "platform" => platform,
      "platform_en" => platform_en
    }.compact
  end
end
