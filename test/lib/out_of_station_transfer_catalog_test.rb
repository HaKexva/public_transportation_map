# frozen_string_literal: true

require "test_helper"

class OutOfStationTransferCatalogTest < ActiveSupport::TestCase
  TRANSFERS_PATH = Rails.root.join("public/geojson/out_of_station_transfers.json")

  test "passage transfers link taiwan_hsr and tra to metro lines" do
    transfers = JSON.parse(TRANSFERS_PATH.read)
    hsr_transfers = transfers.select { |transfer| transfer["routes"]&.include?("taiwan_hsr") }
    tra_transfers = transfers.select { |transfer| transfer["routes"]&.any? { |route| route.include?("_line") || route == "western_trunk_north" } }

    assert_operator hsr_transfers.length, :>=, 6
    assert_includes tra_transfers.map { |entry| entry["id"] }, "tra_taipei_passage"

    hsr_expected = {
      "hsr_nangang_passage" => %w[taiwan_hsr bannan],
      "hsr_taipei_passage" => %w[taiwan_hsr tamsui_xinyi],
      "hsr_banqiao_passage" => %w[taiwan_hsr bannan],
      "hsr_taichung_passage" => %w[taiwan_hsr green_line],
      "hsr_zuoying_passage" => %w[taiwan_hsr red_line],
      "tra_hsr_taoyuan_passage" => %w[western_trunk_north taiwan_hsr]
    }

    hsr_expected.each do |id, routes|
      transfer = hsr_transfers.find { |entry| entry["id"] == id }
      assert transfer, "expected #{id}"
      assert_equal "passage", transfer["kind"]
      assert_equal routes.sort, transfer["routes"].sort
      assert_equal 2, transfer["endpoints"].length
    end

    tra_taoyuan = tra_transfers.find { |entry| entry["id"] == "tra_airport_taoyuan_passage" }
    assert tra_taoyuan, "expected tra_airport_taoyuan_passage"
    assert_equal "passage", tra_taoyuan["kind"]
    assert_equal %w[airport_mrt western_trunk_north], tra_taoyuan["routes"].sort
    assert_equal 2, tra_taoyuan["endpoints"].length
  end
end
