# frozen_string_literal: true

require "test_helper"

class TransitStationRefTest < ActiveSupport::TestCase
  test "matches metro line prefix refs" do
    assert Transit::StationRef.matches_route?("BL14;O07", line_ref: "BL", route_id: "bannan", system_id: "taipei_metro")
    assert Transit::StationRef.matches_route?("O07", line_ref: "O", route_id: "zhonghe_xinlu", system_id: "taipei_metro")
  end

  test "distinguishes maokong G1 from songshan xindian G01" do
    assert Transit::StationRef.matches_route?("G1;BR01", line_ref: "MG", route_id: "maokong_gondola", system_id: "other")
    assert Transit::StationRef.matches_route?("BR01;G1", line_ref: "BR", route_id: "wenhu_line", system_id: "taipei_metro")
    refute Transit::StationRef.matches_route?("G1", line_ref: "G", route_id: "songshan_xindian", system_id: "taipei_metro")
    assert Transit::StationRef.matches_route?("G01", line_ref: "G", route_id: "songshan_xindian", system_id: "taipei_metro")
    assert Transit::StationRef.matches_route?("G03A", line_ref: "G", route_id: "xiaobitan_branch", system_id: "taipei_metro")
  end

  test "matches tra numeric refs" do
    assert Transit::StationRef.matches_route?("1000", line_ref: "WN", route_id: "western_trunk_north", system_id: "tra")
  end

  test "filters suspended stations" do
    feature = {
      "properties" => {
        "feature_type" => "station",
        "passenger_service" => false
      }
    }

    refute Transit::StationRef.passenger_station?(feature)
  end
end
