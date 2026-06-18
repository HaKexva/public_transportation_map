# frozen_string_literal: true

require "application_system_test_case"

class DashboardTest < ApplicationSystemTestCase
  test "stacks route stops above map on narrow screens" do
    page.driver.browser.manage.window.resize_to(390, 844)
    visit route_path("wenhu_line")

    assert_selector ".route-stop-item", minimum: 5, wait: 10

    layout = page.evaluate_script(<<~JS)
      (() => {
        const body = document.querySelector(".route-page__body")
        const stops = document.querySelector(".route-page__stops")
        const map = document.querySelector(".route-page__map")
        if (!body || !stops || !map) return null

        const bodyRect = body.getBoundingClientRect()
        const stopsRect = stops.getBoundingClientRect()
        const mapRect = map.getBoundingClientRect()

        return {
          stopsTop: stopsRect.top <= bodyRect.top + 2,
          mapBelowStops: mapRect.top >= stopsRect.bottom - 4,
          stopsFullWidth: stopsRect.width >= bodyRect.width - 4
        }
      })()
    JS

    assert layout, "expected route page body with stops and map"
    assert layout["stopsTop"], "expected stops on top"
    assert layout["mapBelowStops"], "expected map below stops"
    assert layout["stopsFullWidth"], "expected stops to span body width"
  ensure
    page.driver.browser.manage.window.resize_to(1400, 900)
  end

  test "navigates to dedicated route page from dashboard" do
    visit root_path

    page.execute_script("document.querySelector(\"a[href='#{route_path('wenhu_line')}']\").click()")

    assert_current_path route_path("wenhu_line")
    assert_selector "h1", text: "文湖線", wait: 10
    assert_selector ".route-stop-item", minimum: 5, wait: 10
    assert_link "← 返回地圖", href: root_path
  end

  test "lists 東門 on tamsui xinyi line between 大安森林公園 and 中正紀念堂" do
    visit route_path("tamsui_xinyi")
    assert_selector ".route-stop-item", minimum: 10, wait: 10

    names = page.all(".route-stop-item__name", minimum: 10, wait: 10).map(&:text)
    assert_includes names, "東門"
    assert names.index("大安森林公園") < names.index("東門")
    assert names.index("東門") < names.index("中正紀念堂")
  end

  test "lists maokong gondola stops in line order including angle stations" do
    visit route_path("maokong_gondola")
    assert_selector ".route-stop-item", minimum: 4, wait: 10

    names = page.all(".route-stop-item__name", minimum: 4, wait: 10).map(&:text)
    assert_equal "動物園", names.first
    assert_equal "貓空", names.last
    assert_includes names, "動物園南"
    assert_includes names, "指南宮"
    assert_includes names, "轉角一（不提供載客）"
    assert_includes names, "轉角二（不提供載客）"
    assert names.index("轉角一（不提供載客）") < names.index("動物園南")
    assert names.index("指南宮") < names.index("貓空")
  end

  test "lists 古亭 and 中正紀念堂 on songshan xindian line in order" do
    visit route_path("songshan_xindian")
    assert_selector ".route-stop-item", minimum: 10, wait: 10

    names = page.all(".route-stop-item__name", minimum: 10, wait: 10).map(&:text)
    assert_includes names, "古亭"
    assert_includes names, "中正紀念堂"
    assert names.index("台電大樓") < names.index("古亭")
    assert names.index("古亭") < names.index("中正紀念堂")
    assert names.index("中正紀念堂") < names.index("小南門")
  end

  test "lists 中山 松江南京 南京復興 on songshan xindian line in order" do
    visit route_path("songshan_xindian")
    assert_selector ".route-stop-item", minimum: 10, wait: 10

    names = page.all(".route-stop-item__name", minimum: 10, wait: 10).map(&:text)
    assert_includes names, "中山"
    assert_includes names, "松江南京"
    assert_includes names, "南京復興"
    assert_not_includes names, "忠孝復興"
    assert names.index("北門") < names.index("中山")
    assert names.index("中山") < names.index("松江南京")
    assert names.index("松江南京") < names.index("南京復興")
  end

  test "lists 大安 on tamsui xinyi line between 信義安和 and 大安森林公園" do
    visit route_path("tamsui_xinyi")
    assert_selector ".route-stop-item", minimum: 10, wait: 10

    names = page.all(".route-stop-item__name", minimum: 10, wait: 10).map(&:text)
    refs = page.all(".route-stop-item__index", minimum: 10, wait: 10).map(&:text)
    assert_includes names, "大安"
    assert_equal "R05", refs[names.index("大安")]
    assert names.index("信義安和") < names.index("大安")
    assert names.index("大安") < names.index("大安森林公園")
  end

  test "lists 忠孝復興 on wenhu line between 大安 and 南京復興" do
    visit route_path("wenhu_line")
    assert_selector ".route-stop-item", minimum: 10, wait: 10

    names = page.all(".route-stop-item__name", minimum: 10, wait: 10).map(&:text)
    assert_includes names, "忠孝復興"
    assert names.index("大安") < names.index("忠孝復興")
    assert names.index("忠孝復興") < names.index("南京復興")
  end

  test "orders zhonghe xinlu stops by line station number including transfer refs" do
    visit route_path("zhonghe_xinlu")

    assert_selector ".route-stop-item", minimum: 10, wait: 10

    indices = page.all(".route-stop-item__index", minimum: 10, wait: 10).map(&:text)
    secondary = page.all(".route-stop-item--transfer .route-stop-item__ref", minimum: 2, wait: 10).map(&:text)

    assert_equal "O01", indices.first
    assert_equal "O54", indices.last
    assert_includes indices, "O07"
    assert_includes indices, "O11"
    assert_includes secondary, "BL14"
    assert_includes secondary, "R13"
    assert indices.index("O07") < indices.index("O08")
    assert indices.index("O11") < indices.index("O12")
  end

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
    assert_button "圖例"

    split_layout = page.evaluate_script(<<~JS)
      (() => {
        const layout = document.querySelector(".map-split-layout")
        const sidebar = document.querySelector(".map-split-layout__sidebar")
        const map = document.getElementById("taiwan-region-map")
        if (!layout || !sidebar || !map) return null

        const layoutRect = layout.getBoundingClientRect()
        const sidebarRect = sidebar.getBoundingClientRect()
        const mapRect = map.getBoundingClientRect()

        return {
          sidebarLeft: sidebarRect.left <= layoutRect.left + 2,
          mapRight: mapRect.right >= layoutRect.right - 2,
          mapLeftOfSidebar: mapRect.left >= sidebarRect.right - 4
        }
      })()
    JS
    assert split_layout, "expected split layout with sidebar and map"
    assert split_layout["sidebarLeft"], "expected sidebar on the left"
    assert split_layout["mapRight"], "expected map on the right"
    assert split_layout["mapLeftOfSidebar"], "expected map to the right of the sidebar"
    assert_selector ".map-split-layout__resizer"
    assert_text "台灣大眾運輸地圖"
    click_button "圖例"
    assert_selector "#map-legend", text: "圖例", wait: 5
    assert_text "普通車"
    assert_text "快慢車交會站"
    assert_button "顯示全部路線"
    assert_button "僅顯示捷運與輕軌"
    assert_selector "#layer-all_metro", visible: :all
    assert_selector "#layer-all_transit", visible: :all
    assert_text "捷運"
    assert_text "台鐵"
    assert_text "其他"
    assert_selector "#layer-maokong_gondola", visible: :all
    assert_selector "#layer-taoyuan_airport_skytrain", visible: :all
    assert_selector "#layer-sun_moon_ropeway", visible: :all
    assert_selector "#layer-green_line", visible: :all
    assert_selector "#layer-red_line", visible: :all
    assert_selector "#layer-orange_line", visible: :all
    assert_selector "#layer-circular_lrt", visible: :all
    assert_selector "#layer-taiwan_hsr", visible: :all
    assert_button "重設視角"
  end

  test "stacks sidebar above map on narrow screens" do
    page.driver.browser.manage.window.resize_to(390, 844)
    visit root_path

    assert_selector "#taiwan-region-map"
    assert_selector ".leaflet-container", wait: 5

    split_layout = page.evaluate_script(<<~JS)
      (() => {
        const layout = document.querySelector(".map-split-layout")
        const sidebar = document.querySelector(".map-split-layout__sidebar")
        const map = document.getElementById("taiwan-region-map")
        if (!layout || !sidebar || !map) return null

        const layoutRect = layout.getBoundingClientRect()
        const sidebarRect = sidebar.getBoundingClientRect()
        const mapRect = map.getBoundingClientRect()

        return {
          sidebarTop: sidebarRect.top <= layoutRect.top + 2,
          mapBelowSidebar: mapRect.top >= sidebarRect.bottom - 4,
          sidebarFullWidth: sidebarRect.width >= layoutRect.width - 4
        }
      })()
    JS

    assert split_layout, "expected split layout with sidebar and map"
    assert split_layout["sidebarTop"], "expected sidebar on top"
    assert split_layout["mapBelowSidebar"], "expected map below the sidebar"
    assert split_layout["sidebarFullWidth"], "expected sidebar to span the layout width"
    assert_no_button "顯示全部路線"
    assert_no_button "重設視角"
    assert_no_button "僅顯示捷運與輕軌"
    assert_no_text "不同捷運系統之間的轉乘皆為站外轉乘"
  ensure
    page.driver.browser.manage.window.resize_to(1400, 900)
  end

  test "shows all transit routes when show all routes is clicked" do
    visit root_path

    within "#taiwan-region-map" do
      assert_selector ".leaflet-tile-pane", wait: 10
    end

    click_button "顯示全部路線"

    assert_selector "#layer-wenhu_line:checked", visible: :all, wait: 15
    assert_selector "#layer-taiwan_hsr:checked", visible: :all, wait: 15
    assert_selector "#layer-maokong_gondola:checked", visible: :all, wait: 15
    assert_selector ".leaflet-overlay-pane path.leaflet-interactive", wait: 15, minimum: 5
  end

  test "shows and hides Wenhu line when the line checkbox is toggled" do
    visit root_path

    within "#taiwan-region-map" do
      assert_selector ".leaflet-tile-pane", wait: 10
    end

    assert_selector "#layer-wenhu_line:not([disabled])", visible: :all, wait: 10

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

  test "shows only main line when Tamsui-Xinyi is toggled alone" do
    visit root_path

    within "#taiwan-region-map" do
      assert_selector ".leaflet-tile-pane", wait: 10
    end

    page.execute_script(<<~JS)
      const checkbox = document.getElementById("layer-tamsui_xinyi")
      checkbox.checked = true
      checkbox.dispatchEvent(new Event("change", { bubbles: true }))
    JS
    assert_selector ".leaflet-overlay-pane path.leaflet-interactive", wait: 10, minimum: 1
    refute page.evaluate_script("document.getElementById('layer-xinbeitou_branch').checked")
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
    assert page.evaluate_script("document.getElementById('layer-xinbeitou_branch').checked")
    assert page.evaluate_script("document.getElementById('layer-xiaobitan_branch').checked")
  end

  test "shows all TRA lines when the system checkbox is toggled" do
    visit root_path

    within "#taiwan-region-map" do
      assert_selector ".leaflet-tile-pane", wait: 10
    end

    page.execute_script(<<~JS)
      const checkbox = document.getElementById("layer-tra")
      checkbox.checked = true
      checkbox.dispatchEvent(new Event("change", { bubbles: true }))
    JS

    assert_selector "#layer-western_trunk_north:checked", visible: :all, wait: 30
    assert_selector "#layer-neiwan_line:checked", visible: :all, wait: 5
    assert_selector "#layer-pingxi_line:checked", visible: :all, wait: 5
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

    assert_selector "#layer-circular:checked", visible: :all, wait: 15
    assert_selector "#layer-ankeng_lrt:checked", visible: :all, wait: 15
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

  test "shows out-of-station transfer link between hsr and taichung green line at HSR Taichung" do
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
      show("taiwan_hsr")
      show("green_line")
    JS

    assert_selector ".leaflet-overlay-pane path.leaflet-interactive", wait: 20, minimum: 2
    assert_selector ".out-of-station-transfer-line", wait: 15, minimum: 1, visible: :all
    assert_selector ".transfer-station-marker", wait: 10, minimum: 2, visible: :all
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

  test "shows in-station transfer marker between wenhu line and maokong gondola at Taipei Zoo" do
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

    assert_selector ".transfer-station-marker", wait: 10, minimum: 1
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

    row = find("a[href='#{route_path('airport_mrt')}']", visible: :all)
    dot = row.find("span[style*='background-color']", match: :first, visible: :all)
    assert_match(/rgb\(0,\s*115,\s*183\)/i, dot[:style])
  end

  test "lists taiwan hsr stops on route page and map" do
    visit route_path("taiwan_hsr")
    assert_selector ".route-stop-item", minimum: 12, wait: 10

    names = page.all(".route-stop-item__name", minimum: 12, wait: 10).map(&:text)
    refs = page.all(".route-stop-item__index", minimum: 12, wait: 10).map(&:text)
    assert_equal "南港", names.first
    assert_equal "左營", names.last
    assert_includes names, "台中"
    assert names.index("新竹") < names.index("苗栗"), "新竹 (05) should be north of 苗栗 (06)"
    assert_equal "05", refs[names.index("新竹")]
    assert_equal "06", refs[names.index("苗栗")]

    visit root_path

    within "#taiwan-region-map" do
      assert_selector ".leaflet-tile-pane", wait: 10
    end

    page.execute_script(<<~JS)
      const checkbox = document.getElementById("layer-taiwan_hsr")
      checkbox.checked = true
      checkbox.dispatchEvent(new Event("change", { bubbles: true }))
    JS
    assert_selector ".leaflet-marker-icon", wait: 10, minimum: 1
  end

  test "skytrain route page lists north and south sections" do
    visit route_path("taoyuan_airport_skytrain")
    assert_selector ".route-stop-item", minimum: 4, wait: 10

    assert_selector ".route-stops-section-heading", text: "北側（管制區內）"
    assert_selector ".route-stops-section-heading", text: "南側（管制區外）"

    names = page.all(".route-stop-item__name", minimum: 4).map(&:text)
    assert_includes names, "第一航廈（北側）"
    assert_includes names, "第二航廈（南側）"
  end

  test "airport mrt route page lists commuter and express sections" do
    visit route_path("airport_mrt")
    assert_selector ".route-stop-item", minimum: 7, wait: 10

    assert_selector ".route-stops-section-heading", text: "普通車"
    assert_selector ".route-stops-section-heading", text: "直達車"

    refs = page.all(".route-stop-item__index", minimum: 7, wait: 10).map(&:text)
    assert_equal "A1", refs.first
    assert_includes refs, "A21"

    express_heading = find(".route-stops-section-heading", text: "直達車")
    express_section_refs = express_heading.all(
      :xpath,
      "./following-sibling::li[./button[contains(@class, 'route-stop-item')]]"
    ).map { |item| item.find(".route-stop-item__index").text }

    assert_equal %w[A1 A3 A8 A12 A13 A18 A21], express_section_refs
  end

  test "danhai lrt layer toggle uses coral line color" do
    visit root_path

    row = find("a[href='#{route_path('danhai_lrt')}']", visible: :all)
    dot = row.find("span[style*='background-color']", match: :first, visible: :all)
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
