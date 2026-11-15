# frozen_string_literal: true

require "test_helper"

class Geojson::BusNamesEnTest < ActiveSupport::TestCase
  setup do
    Geojson::BusNamesEn.phrases = {
      "知本" => "Zhiben", "台東" => "Taitung", "泰武" => "Taiwu", "安康路" => "Ankang Road", "嘉義市" => "Chiayi City"
    }
    Geojson::BusNamesEn.snapshot = {
      routes: { "Taipei" => { "紅1" => "R1" } }, subroutes: {}, operators: { "臺北客運" => "Taipei Bus Co., Ltd." }
    }
  end

  teardown { Geojson::BusNamesEn.reset! }

  test "uses TDX English for a Chinese ref and keeps the via part" do
    assert_equal "R1 (via Ankang Road)", Geojson::BusNamesEn.name_en("紅1 (via 安康路)", ref: "紅1", city_id: "Taipei")
  end

  test "translates route words and place names phrase by phrase" do
    assert_equal "Happiness Bus Taiwu 9", Geojson::BusNamesEn.translate("幸福泰武9路")
    assert_equal "8129A (Taitung to Zhiben Railway Station)", Geojson::BusNamesEn.translate("8129A (台東至知本火車站)")
    assert_equal "detour via Chiayi City School District", Geojson::BusNamesEn.translate("繞駛嘉義市學區")
    assert_equal "Ankang Road, Sec. 1", Geojson::BusNamesEn.translate("安康路一段")
    assert_equal "Provincial Highway 9A", Geojson::BusNamesEn.translate("台9甲線")
  end

  test "leaves ASCII names alone" do
    assert_equal "307", Geojson::BusNamesEn.name_en("307", ref: "307", city_id: "Taipei")
  end

  test "operator names come from TDX, the manual list, or a full translation" do
    assert_equal "Taipei Bus Co., Ltd.", Geojson::BusNamesEn.operator_en("臺北客運")
    assert_equal "Taiwan Taxi", Geojson::BusNamesEn.operator_en("台灣大車隊")
    assert_equal "Taiwu Township Office", Geojson::BusNamesEn.operator_en("泰武鄉公所")
    assert_nil Geojson::BusNamesEn.operator_en("某某客運")
  end
end
