# frozen_string_literal: true

require "application_system_test_case"

class DashboardTest < ApplicationSystemTestCase
  test "shows the map on the home page" do
    visit root_path

    assert_selector "#taiwan-region-map"
    assert_selector ".leaflet-container", wait: 5
  end

  test "shows and hides Wenhu line when the line checkbox is toggled" do
    visit root_path

    within "#taiwan-region-map" do
      assert_selector ".leaflet-tile-pane", wait: 10
    end

    check "layer-wenhu_line", allow_label_click: true
    assert_selector ".leaflet-overlay-pane path.leaflet-interactive", wait: 10, minimum: 1

    page.execute_script(<<~JS)
      const checkbox = document.getElementById("layer-wenhu_line")
      checkbox.checked = false
      checkbox.dispatchEvent(new Event("change", { bubbles: true }))
    JS

    assert_no_selector ".leaflet-overlay-pane path.leaflet-interactive", wait: 5
  end

  test "shows branch line with main line when Tamsui-Xinyi is toggled" do
    visit root_path

    within "#taiwan-region-map" do
      assert_selector ".leaflet-tile-pane", wait: 10
    end

    check "layer-tamsui_xinyi", allow_label_click: true
    assert_selector ".leaflet-overlay-pane path.leaflet-interactive", wait: 10, minimum: 2
  end

  test "shows all Taipei Metro lines when the system checkbox is toggled" do
    visit root_path

    within "#taiwan-region-map" do
      assert_selector ".leaflet-tile-pane", wait: 10
    end

    check "layer-taipei_metro", allow_label_click: true
    assert_selector ".leaflet-overlay-pane path.leaflet-interactive", wait: 15, minimum: 6

    assert_predicate find("#layer-wenhu_line", visible: :all), :checked?
    assert_predicate find("#layer-tamsui_xinyi", visible: :all), :checked?
  end

  test "shows Danhai LRT when the line checkbox is toggled" do
    visit root_path

    within "#taiwan-region-map" do
      assert_selector ".leaflet-tile-pane", wait: 10
    end

    page.execute_script(<<~JS)
      const checkbox = document.getElementById("layer-danhai_lrt")
      checkbox.checked = true
      checkbox.dispatchEvent(new Event("change", { bubbles: true }))
    JS

    assert_selector ".leaflet-overlay-pane path.leaflet-interactive", wait: 10, minimum: 1
  end
end
