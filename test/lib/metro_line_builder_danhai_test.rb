# frozen_string_literal: true

require "test_helper"

class MetroLineBuilderDanhaiTest < ActiveSupport::TestCase
  test "danhai shared stations appear on both lushan and lanhai segments" do
    path = Rails.root.join("public/geojson/new_taipei_metro/danhai_lrt.geojson")
    skip "run bin/rails geojson:new_taipei_metro first" unless path.exist?

    data = JSON.parse(path.read)
    stations = data["features"].select { |feature| feature.dig("properties", "feature_type") == "station" }

    station_refs = stations.map { |feature| feature.dig("properties", "ref") }.uniq

    Geojson::NewTaipeiMetroCatalog::DANHAI_SHARED_STATION_REFS.each do |ref|
      next unless station_refs.include?(ref)

      segments = stations
        .select { |feature| feature.dig("properties", "ref") == ref }
        .map { |feature| feature.dig("properties", "segment") }
        .sort

      assert_equal %w[lanhai lushan], segments, "expected #{ref} on both segments"
    end

    assert_includes station_refs, "V03"
    assert_includes station_refs, "V11"
    assert_includes station_refs, "V27"

    v10_segments = stations
      .select { |feature| feature.dig("properties", "ref") == "V10" }
      .map { |feature| feature.dig("properties", "segment") }

    assert_equal [ "lushan" ], v10_segments.sort, "V10 should only be on 綠山線"

    lanhai_stations = stations
      .select { |feature| feature.dig("properties", "segment") == "lanhai" }
      .map { |feature| feature.dig("properties", "ref") }

    assert_equal %w[V01 V02 V03 V04 V05 V06 V07 V08 V09], lanhai_stations.first(9)
    assert_equal %w[V26 V27 V28], lanhai_stations.select { |ref| ref.in?(%w[V28 V27 V26]) }.sort
    assert_includes station_refs, "V28"

    refute stations.any? { |feature| feature.dig("properties", "station_role").present? },
           "routes should not mark origin/destination terminals"
  end

  test "danhai depot spur enters yard northwest of 崁頂 not west of the platform" do
    path = Rails.root.join("public/geojson/new_taipei_metro/danhai_lrt.geojson")
    data = JSON.parse(path.read)

    kanding = data.fetch("features").find { |feature|
      feature.dig("properties", "feature_type") == "station" &&
        feature.dig("properties", "ref") == "V11"
    }
    spur = data.fetch("features").find { |feature| feature.dig("properties", "depot_id") == "danhai_depot" }
    assert kanding
    assert spur, "expected 淡海車廠支線"

    station = kanding.dig("geometry", "coordinates")
    coords = spur.dig("geometry", "coordinates")
    tip = coords.last

    assert_operator tip[1], :>, station[1] + 0.0015, "spur must run north into the yard"
    assert_operator tip[0], :<, station[0] - 0.001, "spur must run west into the yard body"
    assert_in_delta 121.43306, tip[0], 0.0008
    assert_in_delta 25.20313, tip[1], 0.0008
    refute coords.any? { |_lon, lat| lat > 25.2035 }, "should not loop through the NW yard nose"

    depot = Geojson::MetroDepotCatalog::DEPOTS.find { |entry| entry[:id] == "danhai_depot" }
    assert_in_delta 121.43306, depot[:lon], 0.00001
    assert_in_delta 25.20313, depot[:lat], 0.00001
  end
end
