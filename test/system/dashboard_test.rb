# frozen_string_literal: true

require "application_system_test_case"

class DashboardTest < ApplicationSystemTestCase
  test "shows the map on the home page" do
    visit root_path

    assert_selector "#taiwan-region-map"
    assert_selector ".leaflet-container", wait: 5
    assert_selector "#map-legend", text: "圖例"
    assert_text "台灣大眾運輸地圖"
    assert_text "普通車", visible: :all
    assert_text "直達車停靠站", visible: :all
    assert_button "顯示全部捷運"
    assert_button "重設視角"
  end

  test "shows and hides Wenhu line when the line checkbox is toggled" do
    visit root_path

    within "#taiwan-region-map" do
      assert_selector ".leaflet-tile-pane", wait: 10
    end

    assert_selector "#layer-wenhu_line:not([disabled])", wait: 10

    page.execute_script(<<~JS)
      const checkbox = document.getElementById("layer-wenhu_line")
      checkbox.checked = true
      checkbox.dispatchEvent(new Event("change", { bubbles: true }))
    JS
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

    page.execute_script(<<~JS)
      const checkbox = document.getElementById("layer-tamsui_xinyi")
      checkbox.checked = true
      checkbox.dispatchEvent(new Event("change", { bubbles: true }))
    JS
    assert_selector ".leaflet-overlay-pane path.leaflet-interactive", wait: 10, minimum: 2
  end

  test "shows Beitou as a transfer station when Tamsui-Xinyi is toggled" do
    visit root_path

    within "#taiwan-region-map" do
      assert_selector ".leaflet-tile-pane", wait: 10
    end

    page.execute_script(<<~JS)
      const checkbox = document.getElementById("layer-tamsui_xinyi")
      checkbox.checked = true
      checkbox.dispatchEvent(new Event("change", { bubbles: true }))
    JS

    assert_selector ".transfer-station-marker", wait: 10, minimum: 1
  end

  test "shows all Taipei Metro lines when the system checkbox is toggled" do
    visit root_path

    within "#taiwan-region-map" do
      assert_selector ".leaflet-tile-pane", wait: 10
    end

    page.execute_script(<<~JS)
      const checkbox = document.getElementById("layer-taipei_metro")
      checkbox.checked = true
      checkbox.dispatchEvent(new Event("change", { bubbles: true }))
    JS
    assert_selector ".leaflet-overlay-pane path.leaflet-interactive", wait: 15, minimum: 6

    assert page.evaluate_script("document.getElementById('layer-wenhu_line').checked")
    assert page.evaluate_script("document.getElementById('layer-tamsui_xinyi').checked")
  end

  test "shows out-of-station transfer link between circular and ankeng at Shisizhang" do
    visit root_path

    within "#taiwan-region-map" do
      assert_selector ".leaflet-tile-pane", wait: 10
    end

    page.execute_script(<<~JS)
      const show = (id) => {
        const checkbox = document.getElementById(`layer-${id}`)
        checkbox.checked = true
        checkbox.dispatchEvent(new Event("change", { bubbles: true }))
      }
      show("circular")
      show("ankeng_lrt")
    JS

    assert_selector ".leaflet-overlay-pane path.leaflet-interactive", wait: 10, minimum: 2
  end

  test "shows out-of-station transfer link between circular and airport mrt at Xinbei Industrial Park" do
    visit root_path

    within "#taiwan-region-map" do
      assert_selector ".leaflet-tile-pane", wait: 10
    end

    page.execute_script(<<~JS)
      const show = (id) => {
        const checkbox = document.getElementById(`layer-${id}`)
        checkbox.checked = true
        checkbox.dispatchEvent(new Event("change", { bubbles: true }))
      }
      show("circular")
      show("airport_mrt")
    JS

    assert_selector ".leaflet-overlay-pane path.leaflet-interactive", wait: 10, minimum: 2
  end

  test "shows out-of-station transfer links from airport mrt taipei main to beimen and mrt taipei main" do
    visit root_path

    within "#taiwan-region-map" do
      assert_selector ".leaflet-tile-pane", wait: 10
    end

    page.execute_script(<<~JS)
      const show = (id) => {
        const checkbox = document.getElementById(`layer-${id}`)
        checkbox.checked = true
        checkbox.dispatchEvent(new Event("change", { bubbles: true }))
      }
      show("airport_mrt")
      show("songshan_xindian")
      show("tamsui_xinyi")
    JS

    assert_selector ".leaflet-overlay-pane path.leaflet-interactive", wait: 10, minimum: 2
  end

  test "shows out-of-station transfer link between airport mrt and zhonghe xinlu at Sanchong" do
    visit root_path

    within "#taiwan-region-map" do
      assert_selector ".leaflet-tile-pane", wait: 10
    end

    page.execute_script(<<~JS)
      const show = (id) => {
        const checkbox = document.getElementById(`layer-${id}`)
        checkbox.checked = true
        checkbox.dispatchEvent(new Event("change", { bubbles: true }))
      }
      show("airport_mrt")
      show("zhonghe_xinlu")
    JS

    assert_selector ".out-of-station-transfer-line", wait: 10, minimum: 1
    assert_selector ".out-of-station-marker", wait: 10, minimum: 2
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

  test "shows airport mrt express line and stops with the main airport line" do
    visit root_path

    within "#taiwan-region-map" do
      assert_selector ".leaflet-tile-pane", wait: 10
    end

    page.execute_script(<<~JS)
      const checkbox = document.getElementById("layer-airport_mrt")
      checkbox.checked = true
      checkbox.dispatchEvent(new Event("change", { bubbles: true }))
    JS

    assert_selector ".leaflet-overlay-pane path.leaflet-interactive", wait: 10, minimum: 2
    assert_selector "path.airport-mrt-express-line", wait: 10, minimum: 1
    assert_selector ".express-stop-marker", wait: 10, minimum: 1
  end
end
