# frozen_string_literal: true

require "test_helper"

class TransitTransferCatalogTest < ActiveSupport::TestCase
  test "marks hsinchu hsr and liujia transfer at liujia hub" do
    liujia_line = Geojson::TraCatalog::LINES.find { |entry| entry.slug == "liujia_line" }
    western_trunk_north = Geojson::TraCatalog::LINES.find { |entry| entry.slug == "western_trunk_north" }
    hub = Geojson::TransitTransferCatalog::HSINCHU_HSR_HUB

    {
      [ "新竹", Geojson::HsrCatalog::LINES.first ] => "05;1194",
      [ "六家", liujia_line ] => "1194;05"
    }.each do |(name, line), expected_ref|
      entry = Geojson::TransitTransferCatalog.transfer_for(name, line: line)

      assert_equal expected_ref, entry.combined_ref
      assert_in_delta hub[:lon], entry.lon, 0.0001
      assert_in_delta hub[:lat], entry.lat, 0.0001
    end

    assert_nil Geojson::TransitTransferCatalog.transfer_for("新竹", line: western_trunk_north, ref: "1210")
  end

  test "marks tainan hsr and shalun transfer at shalun hub" do
    western_trunk_south = Geojson::TraCatalog::LINES.find { |entry| entry.slug == "western_trunk_south" }
    shalun_line = Geojson::TraCatalog::LINES.find { |entry| entry.slug == "shalun_line" }

    {
      [ "台南", Geojson::HsrCatalog::LINES.first ] => "11;4272",
      [ "沙崙", shalun_line ] => "4272;11"
    }.each do |(name, line), expected_ref|
      entry = Geojson::TransitTransferCatalog.transfer_for(name, line: line)

      assert_equal expected_ref, entry.combined_ref
    end

    assert_nil Geojson::TransitTransferCatalog.transfer_for("臺南", line: western_trunk_south, ref: "4220")
  end

  test "marks banqiao hsr tra and metro transfer at banqiao hub" do
    western_trunk_north = Geojson::TraCatalog::LINES.find { |entry| entry.slug == "western_trunk_north" }
    bannan = Geojson::TaipeiMetroCatalog::LINES.find { |entry| entry.slug == "bannan" }
    circular = Geojson::TaipeiMetroCatalog::LINES.find { |entry| entry.slug == "circular" }

    {
      [ "板橋", Geojson::HsrCatalog::LINES.first ] => "03;1020;BL07",
      [ "板橋", western_trunk_north ] => "1020;BL07;03"
    }.each do |(name, line), expected_ref|
      entry = Geojson::TransitTransferCatalog.transfer_for(name, line: line)

      assert_equal expected_ref, entry.combined_ref
    end

    assert_nil Geojson::TransitTransferCatalog.transfer_for("板橋", line: circular)
  end

  test "does not mark main-line tra junction transfer at changhua" do
    line = Geojson::TraCatalog::LINES.find { |entry| entry.slug == "mountain_line" }

    assert_nil Geojson::TransitTransferCatalog.transfer_for("彰化", line: line)
  end

  test "does not mark main-line tra junction transfers at zhunan or badu" do
    [
      [ "竹南", "mountain_line" ],
      [ "八堵", "western_trunk_north" ],
      [ "花蓮", "beihui_line" ]
    ].each do |name, slug|
      line = Geojson::TraCatalog::LINES.find { |entry| entry.slug == slug }

      assert_nil Geojson::TransitTransferCatalog.transfer_for(name, line: line)
    end
  end

  test "does not mark tra branch junction stations as transfers" do
    {
      "chengzhui_line" => "成功",
      "neiwan_line" => "北新竹"
    }.each do |slug, name|
      line = Geojson::TraCatalog::LINES.find { |entry| entry.slug == slug }

      assert_nil Geojson::TransitTransferCatalog.transfer_for(name, line: line)
    end
  end

  test "marks maokong transfer at taipei zoo" do
    line = Geojson::OtherTransitCatalog::LINES.find { |entry| entry.slug == "maokong_gondola" }
    entry = Geojson::TransitTransferCatalog.transfer_for("動物園", line: line)

    assert_equal "G1;BR01", entry.combined_ref
  end

  test "marks metro transfer at songshan for tra interchange" do
    line = Geojson::TaipeiMetroCatalog::LINES.find { |entry| entry.slug == "songshan_xindian" }
    entry = Geojson::TransitTransferCatalog.transfer_for("松山", line: line)

    assert_equal "G19;990", entry.combined_ref
  end

  test "marks taichung hsr tra and metro transfer at xinwuri hub" do
    mountain_line = Geojson::TraCatalog::LINES.find { |entry| entry.slug == "mountain_line" }
    {
      [ "台中", Geojson::HsrCatalog::LINES.first ] => "07;3340;119",
      [ "高鐵臺中站", Geojson::TaichungMetroCatalog::LINES.first ] => "119;07;3340",
      [ "新烏日", mountain_line ] => "3340;07;119"
    }.each do |(name, line), expected_ref|
      entry = Geojson::TransitTransferCatalog.transfer_for(name, line: line)

      assert_equal expected_ref, entry.combined_ref
    end
  end

  test "marks nangang hsr tra and metro transfer at nangang hub" do
    western_trunk_north = Geojson::TraCatalog::LINES.find { |entry| entry.slug == "western_trunk_north" }
    bannan = Geojson::TaipeiMetroCatalog::LINES.find { |entry| entry.slug == "bannan" }

    {
      [ "南港", Geojson::HsrCatalog::LINES.first ] => "01;980;BL22",
      [ "南港", bannan ] => "BL22;980;01",
      [ "南港", western_trunk_north ] => "980;BL22;01"
    }.each do |(name, line), expected_ref|
      entry = Geojson::TransitTransferCatalog.transfer_for(name, line: line)

      assert_equal expected_ref, entry.combined_ref
    end
  end

  test "marks zuoying hsr tra and metro transfer at xinzuoying hub" do
    western_trunk_south = Geojson::TraCatalog::LINES.find { |entry| entry.slug == "western_trunk_south" }

    {
      [ "左營", Geojson::HsrCatalog::LINES.first ] => "12;4340;R16",
      [ "左營", Geojson::KaohsiungMetroCatalog::LINES.find { |entry| entry.slug == "red_line" } ] => "R16;4340;12",
      [ "新左營", western_trunk_south ] => "4340;12;R16"
    }.each do |(name, line), expected_ref|
      entry = Geojson::TransitTransferCatalog.transfer_for(name, line: line)

      assert_equal expected_ref, entry.combined_ref
    end
  end

  test "does not link downtown kaohsiung tra 4350 to hsr 12" do
    western_trunk_south = Geojson::TraCatalog::LINES.find { |entry| entry.slug == "western_trunk_south" }

    assert_nil Geojson::TransitTransferCatalog.transfer_for("左營(舊城)", line: western_trunk_south, ref: "4350")
  end

  test "does not mark chengzhui junction stations as tra transfers" do
    mountain_line = Geojson::TraCatalog::LINES.find { |entry| entry.slug == "mountain_line" }
    sea_line = Geojson::TraCatalog::LINES.find { |entry| entry.slug == "sea_line" }
    chengzhui_line = Geojson::TraCatalog::LINES.find { |entry| entry.slug == "chengzhui_line" }

    [
      [ "成功", mountain_line ],
      [ "成功", chengzhui_line ],
      [ "追分", sea_line ],
      [ "追分", chengzhui_line ]
    ].each do |name, line|
      assert_nil Geojson::TransitTransferCatalog.transfer_for(name, line: line)
    end
  end

  test "does not link downtown taichung tra 3300 to hsr 07" do
    mountain_line = Geojson::TraCatalog::LINES.find { |entry| entry.slug == "mountain_line" }

    assert_nil Geojson::TransitTransferCatalog.transfer_for("臺中", line: mountain_line, ref: "3300")
    assert_nil Geojson::TransitTransferCatalog.transfer_for("台中", line: mountain_line, ref: "3300")
  end

  test "marks taipei hsr and tra transfer at taipei main hub" do
    western_trunk_north = Geojson::TraCatalog::LINES.find { |entry| entry.slug == "western_trunk_north" }
    airport_mrt = Geojson::TaoyuanMetroCatalog::LINES.find { |entry| entry.slug == "airport_mrt" }

    {
      [ "台北", Geojson::HsrCatalog::LINES.first ] => "02;1000;R10;BL12",
      [ "台北車站", western_trunk_north ] => "1000;R10;BL12;02",
      [ "臺北", western_trunk_north ] => "1000;R10;BL12;02"
    }.each do |(name, line), expected_ref|
      entry = Geojson::TransitTransferCatalog.transfer_for(name, line: line)

      assert_equal expected_ref, entry.combined_ref
    end

    assert_nil Geojson::TransitTransferCatalog.transfer_for("台北車站", line: airport_mrt)
  end
end
