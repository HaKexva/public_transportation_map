# frozen_string_literal: true

require "test_helper"

class RoutesManifestWriterTest < ActiveSupport::TestCase
  test "circular line is listed under new taipei metro not taipei metro" do
    path = Rails.root.join("tmp", "routes_manifest_test_#{name}.json")
    Geojson::RoutesManifestWriter.write!(path: path)

    manifest = JSON.parse(path.read)
    taipei_ids = manifest.fetch("taipei_metro").map { |entry| entry["id"] }
    new_taipei_ids = manifest.fetch("new_taipei_metro").map { |entry| entry["id"] }

    assert_not_includes taipei_ids, "circular"
    assert_includes new_taipei_ids, "circular"
    assert_includes new_taipei_ids, "ankeng_lrt"
    assert_includes new_taipei_ids, "sanying_line"
  ensure
    path.delete if path.exist?
  end

  test "taoyuan metro manifest includes airport mrt express branch" do
    path = Rails.root.join("tmp", "routes_manifest_test_#{name}.json")
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

  test "manifest entries include passenger station names for search" do
    path = Rails.root.join("tmp", "routes_manifest_test_#{name}.json")
    Geojson::RoutesManifestWriter.write!(path: path)

    manifest = JSON.parse(path.read)
    bannan = manifest.fetch("taipei_metro").find { |entry| entry["id"] == "bannan" }

    assert bannan, "expected bannan in manifest"
    assert_includes Array(bannan["station_names"]), "頂埔"
    assert_includes Array(bannan["station_names"]), "BL01"
  ensure
    path.delete if path.exist?
  end
end
