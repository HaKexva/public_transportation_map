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
    assert_not_includes new_taipei_ids, "danhai_lrt"
    assert_includes new_taipei_ids, "danhai_lushan"
    assert_includes new_taipei_ids, "danhai_lanhai"
  ensure
    path.delete if path.exist?
  end

  test "taipei metro lists 棕紅綠橘藍 then 安坑 三鶯 and pilot buses" do
    path = Rails.root.join("tmp", "routes_manifest_test_#{name}.json")
    Geojson::RoutesManifestWriter.write!(path: path)

    manifest = JSON.parse(path.read)
    taipei_ids = manifest.fetch("taipei_metro").map { |entry| entry["id"] }
    new_taipei_ids = manifest.fetch("new_taipei_metro").map { |entry| entry["id"] }

    expected_prefix = %w[
      wenhu_line tamsui_xinyi xinbeitou_branch
      songshan_xindian xiaobitan_branch
      zhonghe_xinlu bannan
      ankeng_lrt sanying_line
      new_taipei_985_xiandao_d20c01d95e
      new_taipei_629_xiandao_447f13f5ac
      new_taipei_lan_2_xiandao_03ad35aed7
    ]
    assert_equal expected_prefix, taipei_ids.first(expected_prefix.length)
    assert_not_includes new_taipei_ids, "ankeng_lrt"
    assert_not_includes new_taipei_ids, "sanying_line"
  ensure
    path.delete if path.exist?
  end

  test "new taipei metro manifest lists danhai green mountain and blue coast layers" do
    path = Rails.root.join("tmp", "routes_manifest_test_#{name}.json")
    Geojson::RoutesManifestWriter.write!(path: path)

    manifest = JSON.parse(path.read)
    new_taipei = manifest.fetch("new_taipei_metro")
    lushan = new_taipei.find { |entry| entry["id"] == "danhai_lushan" }
    lanhai = new_taipei.find { |entry| entry["id"] == "danhai_lanhai" }

    assert lushan, "expected danhai_lushan in manifest"
    assert lanhai, "expected danhai_lanhai in manifest"
    assert_equal "/geojson/new_taipei_metro/danhai_lushan.geojson", lushan["file"]
    assert_equal "/geojson/new_taipei_metro/danhai_lanhai.geojson", lanhai["file"]
    assert_equal "danhai_lrt", lushan["branch_of"]
    assert_equal "danhai_lrt", lanhai["branch_of"]
    assert_equal "綠山線", lushan["name"]
    assert_equal "藍海線", lanhai["name"]
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

  test "bus manifest is written separately without stop names" do
    path = Rails.root.join("tmp", "routes_manifest_test_#{name}.json")
    bus_path = Rails.root.join("tmp", "bus_manifest_test_#{name}.json")
    Geojson::RoutesManifestWriter.write!(path: path, bus_path: bus_path)

    manifest = JSON.parse(path.read)
    assert_nil manifest["bus"]

    buses = Geojson::RoutesManifestWriter.bus_entries(bus_path: bus_path)
    skip "import Keelung buses first" if buses.empty?

    sample = buses.find { |entry| entry["id"].to_s.start_with?("keelung_") } || buses.first
    assert sample
    assert_nil sample["station_names"]
  ensure
    path.delete if path&.exist?
    bus_path.delete if bus_path&.exist?
  end

  test "manifest entries use distinct refs for colliding line codes" do
    path = Rails.root.join("tmp", "routes_manifest_test_#{name}.json")
    Geojson::RoutesManifestWriter.write!(path: path)

    manifest = JSON.parse(path.read)
    tra = manifest.fetch("tra")
    other = manifest.fetch("other")
    sugar = manifest.fetch("sugar_railway")

    shalun = tra.find { |entry| entry["id"] == "shalun_line" }
    south_link = tra.find { |entry| entry["id"] == "south_link" }
    taipingshan = other.find { |entry| entry["id"] == "taipingshan_forest_railway" }
    taichung_port = tra.find { |entry| entry["id"] == "taichung_port_line" }
    wushulin = sugar.find { |entry| entry["id"] == "wushulin_sugar_railway" }
    western_south = tra.find { |entry| entry["id"] == "western_trunk_south" }

    assert_equal "SAL", shalun["ref"]
    assert_equal "SL", south_link["ref"]
    assert_not_equal shalun["ref"], south_link["ref"]
    assert_equal "TPS", taipingshan["ref"]
    assert_equal "TP", taichung_port["ref"]
    assert_not_equal taipingshan["ref"], taichung_port["ref"]
    assert_equal "WSL", wushulin["ref"]
    assert_equal "WS", western_south["ref"]
    assert_not_equal wushulin["ref"], western_south["ref"]
    assert_includes Array(wushulin["station_names"]), "WSL01"
    assert_includes Array(wushulin["station_names"]), "烏樹林"
    refute_includes Array(wushulin["station_names"]), "WS01"
  ensure
    path.delete if path.exist?
  end
end
