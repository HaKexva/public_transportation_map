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

    v26 = stations.find { |feature| feature.dig("properties", "ref") == "V26" }
    v28 = stations.find { |feature| feature.dig("properties", "ref") == "V28" }

    assert_equal "destination", v26.dig("properties", "station_role"), "藍海線終點應為淡水漁人碼頭 (V26)"
    assert_nil v28.dig("properties", "station_role"), "臺北海洋大學 (V28) 不應標示為起迄站"
  end
end
