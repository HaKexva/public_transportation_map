# frozen_string_literal: true
require "application_system_test_case"

class MapSmokeTest < ApplicationSystemTestCase
  test "checkboxes stops official map and route pages work" do
    visit root_path
    assert_selector ".map-boot-overlay[hidden]", visible: :all, wait: 30
    assert_no_selector ".map-split-layout.is-booting"

    find("#layer-wenhu_line", visible: :all).check
    assert_selector ".route-stop-item", minimum: 5, wait: 15
    assert_selector "[data-map-target='routeStopsPanel'].flex", wait: 5

    visit route_path("wenhu_line")
    assert_selector ".route-stop-item", minimum: 5, wait: 20
    assert_no_selector ".route-page.is-booting", wait: 10

    visit root_path
    assert_selector ".map-boot-overlay[hidden]", visible: :all, wait: 30
    find(".map-transport-mode__chip", text: "公車").click
    find(".bus-fold__trigger", text: "基隆市").click
    find(".bus-fold__trigger", text: "100-199").click
    assert_selector "[data-map-target~='busRouteBucket'][data-hydrated='true']", wait: 10
    find("#layer-keelung_101_xiangfeng", visible: :all).check
    assert_selector ".route-stop-item", minimum: 5, wait: 15

    visit route_path("keelung_r66")
    assert_selector ".route-stop-item", minimum: 1, wait: 20
    find(".route-view-switcher [data-view='official']").click
    assert_selector ".route-official-panel__image[src]", wait: 10
  end
end
