# frozen_string_literal: true

require "application_system_test_case"

class DashboardTest < ApplicationSystemTestCase
  test "filters sidebar routes from the search box" do
    visit root_path

    assert_selector "#layer-search", wait: 10
    assert_selector "#layer-wenhu_line", visible: :all
    assert_selector "#layer-circular", visible: :all

    fill_in "layer-search", with: "環狀"

    assert_selector "#layer-circular", visible: :all
    assert_no_selector "#layer-wenhu_line", visible: :visible

    page.execute_script(<<~JS)
      document.querySelector('[data-map-target="layerSearchClear"]').click()
    JS

    assert_selector "#layer-wenhu_line", visible: :all
  end

  test "shows the map on the home page" do
    visit root_path

    assert_selector "#taiwan-region-map"
    assert_selector ".leaflet-container", wait: 5
    assert_selector "#map-legend", text: "圖例"

    legend_on_right = page.evaluate_script(<<~JS)
      (() => {
        const legend = document.getElementById("map-legend")
        if (!legend) return false
        const rect = legend.getBoundingClientRect()
        return rect.left > window.innerWidth / 2
      })()
    JS
    assert legend_on_right, "expected #map-legend on the right half of the viewport"
    assert_text "台灣大眾運輸地圖"
    legend_text = page.evaluate_script("document.getElementById('map-legend')?.textContent || ''")
    assert_includes legend_text, "普通車"
    assert_includes legend_text, "快慢車交會站"

    chevron_toggle = page.evaluate_script(<<~JS)
      (() => {
        const button = document.querySelector("#map-legend .map-ui-panel__toggle")
        const paths = button?.querySelector("svg")?.querySelectorAll("path") || []
        return paths.length === 1
      })()
    JS
    assert chevron_toggle, "legend toggle should use a chevron, not an X icon"
    assert_button "顯示全部捷運"
    assert_text "其他"
    assert_selector "#layer-maokong_gondola"
    assert_selector "#layer-taoyuan_airport_skytrain"
    assert_selector "#layer-sun_moon_ropeway"
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

    assert_selector ".out-of-station-transfer-line", wait: 10, minimum: 1
    assert_selector ".out-of-station-marker", wait: 10, minimum: 2
  end

  test "shows Shisizhang out-of-station transfer when new taipei metro system is toggled" do
    visit root_path

    within "#taiwan-region-map" do
      assert_selector ".leaflet-tile-pane", wait: 10
    end

    page.execute_script(<<~JS)
      const checkbox = document.getElementById("layer-new_taipei_metro")
      checkbox.checked = true
      checkbox.dispatchEvent(new Event("change", { bubbles: true }))
    JS

    assert page.evaluate_script("document.getElementById('layer-circular').checked")
    assert page.evaluate_script("document.getElementById('layer-ankeng_lrt').checked")
    assert_selector ".leaflet-overlay-pane path.leaflet-interactive", wait: 20, minimum: 3
    assert_selector ".out-of-station-transfer-line", wait: 15, minimum: 1, visible: :all
    assert_selector ".out-of-station-marker", wait: 10, minimum: 2
  end

  test "shows out-of-station transfer link between bannan and circular at Banqiao" do
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
      show("bannan")
      show("circular")
    JS

    assert_selector ".out-of-station-transfer-line", wait: 10, minimum: 1
    assert_selector ".out-of-station-transfer-line--fare-discount", wait: 10, minimum: 1
    assert_selector ".out-of-station-marker", wait: 10, minimum: 2
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

    assert_selector ".out-of-station-transfer-line", wait: 10, minimum: 1
    assert_selector ".out-of-station-marker", wait: 10, minimum: 2
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

  test "shows out-of-station transfer link between tamsui xinyi and danhai lrt at Hongshulin" do
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
      show("tamsui_xinyi")
      show("danhai_lrt")
    JS

    assert_selector ".out-of-station-transfer-line", wait: 10, minimum: 1
    assert_selector ".out-of-station-marker", wait: 10, minimum: 2
  end

  test "shows out-of-station transfer link between wenhu line and maokong gondola at Taipei Zoo" do
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
      show("wenhu_line")
      show("maokong_gondola")
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

    assert_selector "path.airport-mrt-commuter-line", wait: 10, minimum: 1
    assert_selector "path.airport-mrt-express-line", wait: 10, minimum: 1
    assert_selector ".transfer-station-marker", wait: 10, minimum: 1
    assert_selector ".leaflet-stationMarkers-pane .leaflet-interactive", wait: 10, minimum: 1
  end

  test "airport mrt layer toggle uses commuter blue" do
    visit root_path

    dot = find("label[for='layer-airport_mrt'] span[style*='background-color']", visible: :all)
    assert_match(/rgb\(0,\s*115,\s*183\)/i, dot[:style])
  end

  test "danhai lrt layer toggle uses coral line color" do
    visit root_path

    dot = find("label[for='layer-danhai_lrt'] span[style*='background-color']", visible: :all)
    assert_match(/rgb\(237,\s*107,\s*70\)/i, dot[:style])
  end

  test "airport mrt map shows blue commuter and purple express solid lines" do
    visit root_path

    within "#taiwan-region-map" do
      assert_selector ".leaflet-tile-pane", wait: 10
    end

    page.execute_script(<<~JS)
      const checkbox = document.getElementById("layer-airport_mrt")
      checkbox.checked = true
      checkbox.dispatchEvent(new Event("change", { bubbles: true }))
    JS

    assert_selector "path.airport-mrt-express-line", wait: 10, minimum: 1

    colors = page.evaluate_script(<<~JS)
      ({
        commuter: Array.from(document.querySelectorAll("path.airport-mrt-commuter-line"))
          .map((path) => (path.getAttribute("stroke") || path.style.stroke || "").toLowerCase())
          .filter(Boolean),
        express: Array.from(document.querySelectorAll("path.airport-mrt-express-line"))
          .map((path) => (path.getAttribute("stroke") || path.style.stroke || "").toLowerCase())
          .filter(Boolean)
      })
    JS

    assert colors["commuter"].any?, "expected commuter line path"
    assert colors["express"].any?, "expected express line path"

    assert colors["commuter"].any? { |stroke| stroke.include?("0073b7") || stroke.include?("0, 115, 183") },
           "expected commuter blue line, got: #{colors["commuter"].inspect}"
    assert colors["express"].any? { |stroke| stroke.include?("6a2c91") || stroke.include?("106, 44, 145") },
           "expected express purple line, got: #{colors["express"].inspect}"

    commuter_z = page.evaluate_script("document.querySelector('.leaflet-commuterRoutes-pane')?.style.zIndex")
    express_z = page.evaluate_script("document.querySelector('.leaflet-expressRoutes-pane')?.style.zIndex")
    station_z = page.evaluate_script("document.querySelector('.leaflet-stationMarkers-pane')?.style.zIndex")
    assert commuter_z.present? && express_z.present? && station_z.present?
    assert commuter_z.to_i > express_z.to_i, "expected commuter pane (z=#{commuter_z}) above express pane (z=#{express_z})"
    assert station_z.to_i > commuter_z.to_i, "expected station pane (z=#{station_z}) above commuter pane (z=#{commuter_z})"
  end

  test "airport mrt express line renders as solid purple" do
    visit root_path

    within "#taiwan-region-map" do
      assert_selector ".leaflet-tile-pane", wait: 10
    end

    page.execute_script(<<~JS)
      const checkbox = document.getElementById("layer-airport_mrt")
      checkbox.checked = true
      checkbox.dispatchEvent(new Event("change", { bubbles: true }))
    JS

    express_path = find("path.airport-mrt-express-line", wait: 10, match: :first)
    dash = express_path[:style].to_s[/stroke-dasharray:\s*([^;]+)/i, 1]
    assert dash.blank?, "expected solid express line, got dasharray: #{dash}"
  end
end
