# frozen_string_literal: true

require "test_helper"

class OutOfStationTransferCatalogTest < ActiveSupport::TestCase
  TRANSFERS_PATH = Rails.root.join("public/geojson/out_of_station_transfers.json")

  test "hsr passage transfers link taiwan_hsr to metro lines" do
    transfers = JSON.parse(TRANSFERS_PATH.read)
    hsr_transfers = transfers.select { |transfer| transfer["routes"]&.include?("taiwan_hsr") }

    assert_equal 6, hsr_transfers.length

    expected = {
      "hsr_nangang_passage" => %w[taiwan_hsr bannan],
      "hsr_taipei_passage" => %w[taiwan_hsr tamsui_xinyi],
      "hsr_banqiao_passage" => %w[taiwan_hsr bannan],
      "hsr_taoyuan_passage" => %w[taiwan_hsr airport_mrt],
      "hsr_taichung_passage" => %w[taiwan_hsr green_line],
      "hsr_zuoying_passage" => %w[taiwan_hsr red_line]
    }

    expected.each do |id, routes|
      transfer = hsr_transfers.find { |entry| entry["id"] == id }
      assert transfer, "expected #{id}"
      assert_equal "passage", transfer["kind"]
      assert_equal routes.sort, transfer["routes"].sort
      assert_equal 2, transfer["endpoints"].length
    end
  end
end
