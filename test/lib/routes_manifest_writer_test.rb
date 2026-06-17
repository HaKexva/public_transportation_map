# frozen_string_literal: true

require "test_helper"

class RoutesManifestWriterTest < ActiveSupport::TestCase
  test "circular line is listed under new taipei metro not taipei metro" do
    path = Rails.root.join("tmp/routes_manifest_test.json")
    Geojson::RoutesManifestWriter.write!(path: path)

    manifest = JSON.parse(path.read)
    taipei_ids = manifest.fetch("taipei_metro").map { |entry| entry["id"] }
    new_taipei_ids = manifest.fetch("new_taipei_metro").map { |entry| entry["id"] }

    assert_not_includes taipei_ids, "circular"
    assert_includes new_taipei_ids, "circular"
    assert_includes new_taipei_ids, "ankeng_lrt"
  ensure
    path.delete if path.exist?
  end

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
