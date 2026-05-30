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
  end
end
