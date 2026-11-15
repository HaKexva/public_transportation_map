# frozen_string_literal: true

require "test_helper"

class Geojson::BusNightMergerTest < ActiveSupport::TestCase
  LINE = [ [ 121.50, 25.00 ], [ 121.51, 25.00 ] ].freeze

  setup { @dir = Dir.mktmpdir }
  teardown { FileUtils.remove_entry(@dir) }

  test "folds a night route running the day route's stops and path into it" do
    write("taipei_39", collection("39", %w[甲 乙], LINE))
    write("taipei_39_night", collection("39夜", %w[甲 乙], LINE))

    assert_equal [ "taipei_39_night" ], Geojson::BusNightMerger.process_city_dir!(@dir)
    assert_not File.exist?(File.join(@dir, "taipei_39_night.geojson"))
    assert_equal [ "39夜" ], read("taipei_39").dig("properties", "merged_refs")
  end

  test "keeps a night route that serves different stops" do
    write("taipei_212", collection("212", %w[甲 乙], LINE))
    write("taipei_212_night", collection("212夜", %w[甲 丙], LINE))

    assert_empty Geojson::BusNightMerger.process_city_dir!(@dir)
    assert File.exist?(File.join(@dir, "taipei_212_night.geojson"))
  end

  private

  def collection(ref, stops, line)
    features = [ 0, 1 ].flat_map do |direction|
      route = { "type" => "Feature", "properties" => { "feature_type" => "route", "direction" => direction },
                "geometry" => { "type" => "LineString", "coordinates" => line } }
      stations = stops.each_with_index.map do |name, index|
        { "type" => "Feature", "properties" => { "feature_type" => "station", "direction" => direction, "name" => name },
          "geometry" => { "type" => "Point", "coordinates" => line[index] } }
      end
      [ route ] + stations
    end
    { "type" => "FeatureCollection", "properties" => { "ref" => ref, "city_id" => "Taipei" }, "features" => features }
  end

  def write(slug, data)
    File.write(File.join(@dir, "#{slug}.geojson"), JSON.generate(data))
  end

  def read(slug)
    JSON.parse(File.read(File.join(@dir, "#{slug}.geojson")))
  end
end
