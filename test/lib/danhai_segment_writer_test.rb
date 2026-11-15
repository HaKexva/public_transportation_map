# frozen_string_literal: true

require "test_helper"

class DanhaiSegmentWriterTest < ActiveSupport::TestCase
  test "splits combined danhai geojson into lushan and lanhai layers" do
    Geojson::DanhaiSegmentWriter.write!

    lushan = JSON.parse(Rails.root.join("public/geojson/new_taipei_metro/danhai_lushan.geojson").read)
    lanhai = JSON.parse(Rails.root.join("public/geojson/new_taipei_metro/danhai_lanhai.geojson").read)

    lushan_segments = lushan.fetch("features").filter_map { |feature| feature.dig("properties", "segment") }.uniq
    lanhai_segments = lanhai.fetch("features").filter_map { |feature| feature.dig("properties", "segment") }.uniq

    assert_equal [ "lushan" ], lushan_segments
    assert_equal [ "lanhai" ], lanhai_segments

    lushan_refs = lushan.fetch("features")
      .select { |feature| feature.dig("properties", "feature_type") == "station" }
      .map { |feature| feature.dig("properties", "ref") }
    lanhai_refs = lanhai.fetch("features")
      .select { |feature| feature.dig("properties", "feature_type") == "station" }
      .map { |feature| feature.dig("properties", "ref") }

    assert_includes lushan_refs, "V01"
    assert_includes lushan_refs, "V11"
    assert_includes lanhai_refs, "V01"
    assert_includes lanhai_refs, "V26"
    assert_not_includes lushan_refs, "V26"
    assert_not_includes lanhai_refs, "V11"

    assert lushan.fetch("features").any? { |feature| feature.dig("properties", "feature_type") == "depot_spur" }
    assert lanhai.fetch("features").none? { |feature| feature.dig("properties", "feature_type") == "depot_spur" }
  end
end
