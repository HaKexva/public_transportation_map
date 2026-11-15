# frozen_string_literal: true

require "test_helper"

class Geojson::StationNamesEnTest < ActiveSupport::TestCase
  test "looks up names with 臺/台 and 站 variations" do
    assert_equal "Taipei Main Station", Geojson::StationNamesEn.lookup("台北車站")
    assert_equal "Banqiao", Geojson::StationNamesEn.lookup("板橋站")
    assert_nil Geojson::StationNamesEn.lookup("")
  end

  test "apply! copies English names onto station features" do
    Dir.mktmpdir do |dir|
      root = Pathname.new(dir)
      FileUtils.mkdir_p(root.join("taipei_metro"))
      path = root.join("taipei_metro/bannan.geojson")
      File.write(path, JSON.generate("type" => "FeatureCollection", "features" => [
        { "type" => "Feature", "properties" => { "feature_type" => "station", "name" => "板橋" }, "geometry" => { "type" => "Point", "coordinates" => [ 121.46, 25.01 ] } },
        { "type" => "Feature", "properties" => { "feature_type" => "route", "name" => "板南線" }, "geometry" => { "type" => "LineString", "coordinates" => [] } }
      ]))

      assert_equal 1, Geojson::StationNamesEn.apply!(root:)
      features = JSON.parse(File.read(path))["features"]
      assert_equal "Banqiao", features.first.dig("properties", "name_en")
      assert_nil features.last.dig("properties", "name_en")
      assert_equal 0, Geojson::StationNamesEn.apply!(root:)
    end
  end
end
