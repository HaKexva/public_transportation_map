# frozen_string_literal: true

require "test_helper"

class RoutesManifestWriterTest < ActiveSupport::TestCase
  test "taoyuan metro manifest includes airport mrt express branch" do
    path = Rails.root.join("tmp/routes_manifest_test.json")
    Geojson::RoutesManifestWriter.write!(path: path)

    manifest = JSON.parse(path.read)
    taoyuan = manifest.fetch("taoyuan_metro")
    express = taoyuan.find { |entry| entry["id"] == "airport_mrt_express" }

    assert express, "expected airport_mrt_express in manifest"
    assert_equal "airport_mrt", express["branch_of"]
    assert_equal "/geojson/taoyuan_metro/airport_mrt_express.geojson", express["file"]
  ensure
    path.delete if path.exist?
  end
end
