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

    assert_selector ".map-boot-overlay[hidden]", visible: :all, wait: 30
    assert_selector "a[href='#{route_path('wenhu_line')}']", visible: :all, wait: 5
    page.execute_script(<<~JS)
      const link = document.querySelector("a[href='#{route_path('wenhu_line')}']")
      if (!link) throw new Error("wenhu_line link missing")
      link.scrollIntoView({ block: "center" })
      link.click()
    JS

    assert_selector "h1", text: "文湖線", wait: 15
    assert_current_path route_path("wenhu_line")
    assert_selector ".route-stop-item", minimum: 5, wait: 10
    assert_selector ".time-scrubber", wait: 5
    assert_link "← 返回地圖", href: root_path
  end

  test "shows official map and stops together on a bus route page" do
    visit route_path("keelung_r66")

    assert_selector ".route-stop-item", minimum: 1, wait: 15
    assert_selector ".route-page__map .leaflet-container", wait: 10
    assert_selector ".route-view-switcher", text: "官方路線圖"
    assert_selector ".route-page__stops", text: "站點列表"

    find(".route-view-switcher [data-view='official']").click

    assert_selector ".route-official-panel__image[src]", wait: 10
    assert_selector ".route-stop-item", minimum: 1
    assert_selector ".route-page__map .route-official-panel.flex"
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

  test "shows every station name label on the route map" do
    visit route_path("wenhu_line")
    assert_selector ".route-stop-item", minimum: 10, wait: 10
    assert_selector ".leaflet-container", wait: 5

    stop_names = page.all(".route-stop-item__name", minimum: 10, wait: 10).map(&:text)
    assert_selector ".station-name-label", minimum: stop_names.length, wait: 15

    label_names = page.evaluate_script(<<~JS)
      Array.from(document.querySelectorAll(".station-name-label")).map((el) => el.textContent.trim())
    JS

    missing = stop_names - label_names
    assert_empty missing, "missing map labels: #{missing.inspect}"
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

  test "shows a loading list until the map is ready" do
    visit root_path

    assert_selector ".map-boot-overlay", visible: :all
    assert_selector ".map-boot-overlay__item", visible: :all, minimum: 4, wait: 10
    assert_selector ".map-boot-overlay__bar", visible: :all

    assert_selector ".map-boot-overlay[hidden]", visible: :all, wait: 30
    assert_no_selector ".is-booting"
    assert_selector "#layer-wenhu_line:not([disabled])", visible: :all, wait: 5
    assert_selector "#layer-bannan:not([disabled])", visible: :all, wait: 5
    assert_selector ".map-transport-mode__chip", text: "公車"
  end

  test "filters sidebar routes from the search box" do
    visit root_path

    assert_selector ".map-boot-overlay[hidden]", visible: :all, wait: 30
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

    fill_in "layer-search", with: "頂埔"

    assert_selector "#layer-bannan", visible: :all
    assert_no_selector "#layer-wenhu_line", visible: :visible
  end

  test "shows four region viewpoint chips on the dashboard" do
    visit root_path

    assert_selector ".map-region-switcher", wait: 10
    assert_selector "[data-map-target='regionChip']", count: 4
    assert_selector "[data-region-id='north'][aria-pressed='true']"
    assert_selector "[data-region-id='central']"
    assert_selector "[data-region-id='south']"
    assert_selector "[data-region-id='east']"
  end

  test "shows the map on the home page" do
    visit root_path

    assert_selector "#taiwan-region-map"
    assert_selector ".leaflet-container", wait: 5
    assert_selector ".map-boot-overlay[hidden]", visible: :all, wait: 30
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
    assert_text "轉乘連線"
    assert_text "聯通道／共構轉乘"
    assert_text "站外轉乘（有優惠）"
    assert_text "站外轉乘（無優惠）"
    assert_text "同系統站內轉乘"
    assert_text "快慢車交會站"
    assert_selector "#layer-all_metro", visible: :all
    assert_no_button "僅顯示捷運與輕軌"
    assert_no_text "全部路線"
    assert_selector ".layer-category-chip", text: "捷運與輕軌"
    assert_selector ".layer-category-chip", text: "台鐵"
    assert_selector ".layer-category-chip", text: "其他"
    assert_selector ".map-transport-mode__chip", text: "公車"
    assert_no_selector ".layer-category-chip", text: "全部"
    assert_text "捷運"
    assert_no_text "即將推出"
    assert_selector "#layer-maokong_gondola", visible: :all
    assert_selector "#layer-taoyuan_airport_skytrain", visible: :all
    assert_selector "#layer-sun_moon_ropeway", visible: :all
    assert_selector "#layer-green_line", visible: :all
    assert_selector "#layer-red_line", visible: :all
    assert_selector "#layer-orange_line", visible: :all
    assert_selector "#layer-circular_lrt", visible: :all
    assert_selector "#layer-airport_mrt_express", visible: :all
    assert_button "重設視角"
    assert_selector "#map-basemap-select"
    assert_selector "#map-basemap-select option", text: "衛星"
    assert_selector "#map-basemap-select option", text: "台灣圖資"
  end

  test "nests city hundreds and highway operator folds on the bus layer" do
    visit bus_map_path
    assert_selector ".map-boot-overlay[hidden]", visible: :all, wait: 30

    assert_equal "/bus", URI.parse(current_url).path
    assert_selector ".map-transport-mode__chip--active", text: "公車"
    assert_selector ".map-region-switcher.is-hidden", visible: :all
    assert_selector ".bus-fold__trigger", text: "大台北"
    assert_selector ".bus-fold__trigger", text: "公路客運"
    assert_no_selector ".bus-fold__trigger", text: "臺北市"
    assert_no_selector ".bus-fold__trigger", text: "新北市"

    find(".bus-fold__trigger", text: "基隆市").click
    assert_selector ".bus-fold__trigger", text: "T, R"
    assert_selector ".bus-fold__trigger", text: "100-199"
    assert_selector ".bus-fold__trigger", text: "200-299"
    assert_selector ".bus-fold__trigger", text: "300-399"
    assert_no_text "基隆市公車處"
    within find(".bus-fold", text: "基隆市") do
      assert_no_selector ".bus-fold__trigger", text: "0-99"
    end

    find(".bus-fold__trigger", text: "100-199").click
    assert_selector "[data-map-target~='busRouteBucket'][data-hydrated='true']", wait: 10
    assert_text "經中正路"
    assert_text "經祥豐街"
    within find(".bus-fold--band", text: "300-399") do
      assert_selector "label", text: "全選"
    end

    find(".bus-fold__trigger", text: "大台北").click

    assert_selector ".bus-fold__trigger", text: "0-99"
    assert_selector ".bus-fold__trigger", text: "100-199"
    assert_selector ".bus-fold__trigger", text: "200-299"
    assert_selector ".bus-fold__trigger", text: "紅線接駁"
    assert_selector ".bus-fold__trigger", text: "藍線接駁"
    assert_selector ".bus-fold__trigger", text: "內科通勤"
    assert_selector ".bus-fold__trigger", text: "內科快線"
    assert_selector ".bus-fold__trigger", text: "南軟專車"
    assert_selector ".bus-fold__trigger", text: "通勤"
    assert_selector ".bus-fold__trigger", text: "幹線"
    assert_selector ".bus-fold__trigger", text: "北士科"
    assert_selector ".bus-fold__trigger", text: "懷恩專車"
    assert_selector ".bus-fold__trigger", text: "地區線"
    assert_no_text "此範圍尚無公車路線資料。"

    find(".bus-fold__trigger", text: "桃園市").click
    assert_selector ".bus-fold__trigger", text: "100-199"
    assert_no_selector ".bus-fold--operator"
  end

  test "switches basemap from the dropdown without breaking the map" do
    visit root_path
    assert_selector ".leaflet-container", wait: 5
    assert_selector "#map-basemap-select"

    select "衛星", from: "map-basemap-select"
    sat_state = page.evaluate_script(<<~JS)
      (() => {
        const select = document.getElementById("map-basemap-select")
        const map = document.querySelector(".leaflet-container")
        return {
          value: select?.value,
          satClass: map?.classList.contains("map-basemap--satellite"),
          tileCount: document.querySelectorAll(".leaflet-tile-pane img.leaflet-tile").length
        }
      })()
    JS
    assert_equal "sat", sat_state["value"]
    assert sat_state["satClass"]
    assert sat_state["tileCount"].positive?

    select "簡化地圖", from: "map-basemap-select"
    assert_equal "carto", page.find("#map-basemap-select").value

    select "台灣圖資", from: "map-basemap-select"
    assert_selector ".leaflet-container"
    assert_equal "nlsc", page.find("#map-basemap-select").value
  end

  test "uses map-first layout with layers sheet on narrow screens" do
    page.driver.browser.manage.window.resize_to(390, 844)
    visit root_path

    assert_selector "#taiwan-region-map"
    assert_selector ".leaflet-container", wait: 5
    assert_button "圖層"
    assert_button "圖例"
    assert_button "重設視角"

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
          mapFullWidth: mapRect.width >= layoutRect.width - 4,
          mapFullHeight: mapRect.height >= layoutRect.height - 4,
          sidebarOffscreen: sidebarRect.top >= layoutRect.bottom - 4 || sidebarRect.bottom <= layoutRect.top + 4
        }
      })()
    JS

    assert split_layout, "expected map-first layout"
    assert split_layout["mapFullWidth"], "expected map to span the layout width"
    assert split_layout["mapFullHeight"], "expected map to span the layout height"
    assert split_layout["sidebarOffscreen"], "expected layers sheet to start off-screen"

    click_button "圖層"
    assert_selector ".map-split-layout--layers-open"
    assert_selector "#layer-search", visible: :visible, wait: 5
    assert_button "重設視角"
    assert_selector "#layer-all_metro", visible: :all
  ensure
    page.driver.browser.manage.window.resize_to(1400, 900)
  end

  test "shows all transit routes when show all routes is clicked" do
    visit root_path

    within "#taiwan-region-map" do
      assert_selector ".leaflet-tile-pane", wait: 10
    end

    assert_selector "#layer-wenhu_line:not([disabled])", visible: :all, wait: 10

    page.execute_script(<<~JS)
      const el = document.querySelector('[data-controller~="map"]')
      const controller = window.Stimulus.getControllerForElementAndIdentifier(el, "map")
      controller.showAllTransit()
    JS

    # Checkboxes sync only after every rail route has loaded, which is slow on shared CI runners.
    assert_selector "#layer-wenhu_line:checked", visible: :all, wait: 45
    assert_selector "#layer-taiwan_hsr:checked", visible: :all, wait: 45
    assert_selector "#layer-maokong_gondola:checked", visible: :all, wait: 45
    assert_selector ".leaflet-overlay-pane path.leaflet-interactive", wait: 15, minimum: 5
  end

  test "express trains do not slow down at through stations" do
    visit root_path
    assert_selector ".map-boot-overlay[hidden]", visible: :all, wait: 30

    result = page.evaluate_script(<<~JS)
      (() => {
        const el = document.querySelector('[data-controller~="map"]')
        const controller = window.Stimulus.getControllerForElementAndIdentifier(el, "map")
        const path = [
          { r: "A", a: 600, d: 600 },
          { r: "B", a: 610, d: 610, t: true },
          { r: "C", a: 620, d: 620 }
        ]
        const vehicle = { system_id: "tra", trip_type: "3" }
        const at = (minute) => controller.placementOnStopPath(path, minute, vehicle)
        const before = at(609.5)
        const after = at(610.5)
        return {
          beforeRef: before.fromRef,
          afterRef: after.fromRef,
          beforeProgress: before.progress,
          afterProgress: after.progress,
          spanFrom: after.spanFromRef,
          spanTo: after.spanToRef
        }
      })()
    JS

    assert_equal "A", result["beforeRef"]
    assert_equal "B", result["afterRef"]
    assert_equal "A", result["spanFrom"]
    assert_equal "C", result["spanTo"]
    # Mid-span the train cruises through B instead of braking into it:
    # per-hop easing would put it at >0.99 / <0.01 either side of the pass.
    assert_in_delta 0.925, result["beforeProgress"], 0.04
    assert_in_delta 0.075, result["afterProgress"], 0.04
  end

  test "canvas trains stay off the DOM and still open popups" do
    visit root_path
    assert_selector ".map-boot-overlay[hidden]", visible: :all, wait: 30

    counts = page.evaluate_script(<<~JS)
      (() => {
        const el = document.querySelector('[data-controller~="map"]')
        const controller = window.Stimulus.getControllerForElementAndIdentifier(el, "map")
        controller.syncVehicleMarkers([{
          id: "test-gps-1", route_id: "taiwan_hsr", system_id: "hsr", train_number: "0999",
          destination_name: "左營", position_source: "tdx_gps", lat: 25.0478, lng: 121.5170
        }])
        controller.handleCanvasVehicleSelect({ id: "test-gps-1" })
        return {
          markers: Object.keys(controller.vehicleMarkersById).length,
          domIcons: document.querySelectorAll(".vehicle-marker-icon").length
        }
      })()
    JS

    assert_equal 1, counts["markers"]
    assert_equal 0, counts["domIcons"]
    find(".leaflet-popup [data-vehicle-follow]").click
    assert_no_selector ".leaflet-popup", wait: 5
    assert_selector ".vehicle-follow-bar:not([hidden])", wait: 5
  end

  test "station board lists the next hour locally and follows without jumping the clock" do
    visit root_path
    assert_selector ".map-boot-overlay[hidden]", visible: :all, wait: 30

    before = page.evaluate_script(<<~JS)
      (() => {
        const el = document.querySelector('[data-controller~="map"]')
        const controller = window.Stimulus.getControllerForElementAndIdentifier(el, "map")
        const now = controller.minutesSinceMidnightFromIso(controller.simulationAt)
        const at = (offset) => (now + offset) % 1440
        controller.scheduleSnapshots["taiwan_hsr"] = {
          date: controller.simulationDateString(),
          route_id: "taiwan_hsr",
          system_id: "hsr",
          trips: [
            { id: "trip:soon", train_number: "0123", destination_name: "左營",
              path: [ { r: "02", a: at(10), d: at(11) }, { r: "03", a: at(20), d: at(21) } ] },
            { id: "trip:later", train_number: "0999", destination_name: "左營",
              path: [ { r: "02", a: at(90), d: at(91) }, { r: "03", a: at(100), d: at(101) } ] }
          ]
        }
        controller.scheduleDate = controller.simulationDateString()
        controller.openStationBoard({ routeId: "taiwan_hsr", ref: "02", name: "台北" })
        return controller.simulationAt
      })()
    JS

    assert_selector ".station-board__row[data-follow-trip='trip:soon']", wait: 5
    assert_no_selector ".station-board__row[data-follow-trip='trip:later']"

    find(".station-board__row[data-follow-trip='trip:soon']").click

    after = page.evaluate_script(<<~JS)
      (() => {
        const el = document.querySelector('[data-controller~="map"]')
        const controller = window.Stimulus.getControllerForElementAndIdentifier(el, "map")
        return { at: controller.simulationAt, pending: controller.pendingFollowTripId, followed: controller.followedVehicleKey }
      })()
    JS

    assert_in_delta Time.iso8601(before).to_f, Time.iso8601(after["at"]).to_f, 120
    assert(after["pending"] == "trip:soon" || after["followed"].to_s.include?("0123"), "expected a pending or active follow for trip:soon, got #{after.inspect}")
  end

  test "share links restore the simulation time and carry it when copied" do
    visit root_path(at: "2026-08-04T08:15", lat: 25.0478, lng: 121.517, z: 13)
    assert_selector ".map-boot-overlay[hidden]", visible: :all, wait: 30

    state = page.evaluate_script(<<~JS)
      (() => {
        const el = document.querySelector('[data-controller~="map"]')
        const controller = window.Stimulus.getControllerForElementAndIdentifier(el, "map")
        controller.followedTrainNumber = "0123"
        return {
          at: controller.simulationAt,
          share: controller.shareUrlPath({ includeTime: true })
        }
      })()
    JS

    assert_equal "2026-08-04T00:15:00.000Z", state["at"]
    share = Rack::Utils.parse_query(URI.parse(state["share"]).query)
    assert_equal "2026-08-04T00:15:00Z", share["at"]
    assert_equal "0123", share["follow"]
    assert_equal "13", share["z"]

    # The live address bar drops `at` so a reload returns to the present.
    assert_no_current_path(/[?&]at=/, wait: 5)
  end

  test "level crossing predicts timetable passes along the hop track" do
    visit root_path
    assert_selector ".map-boot-overlay[hidden]", visible: :all, wait: 30

    rows = page.evaluate_script(<<~JS)
      (() => {
        const el = document.querySelector('[data-controller~="map"]')
        const controller = window.Stimulus.getControllerForElementAndIdentifier(el, "map")
        const now = controller.minutesSinceMidnightFromIso(controller.simulationAt)
        const coords = { A: [ 25.0, 121.0 ], D: [ 25.0, 121.03 ] }
        controller.stationCoordForRef = (ref) => coords[ref] || null
        controller.vehicleTracksByRouteId["test_crossing_line"] = [ [ [ 121.0, 25.0 ], [ 121.03, 25.0 ] ] ]
        controller.scheduleSnapshots["test_crossing_line"] = {
          route_id: "test_crossing_line",
          trips: [
            { id: "trip:x", train_number: "1234", path: [ { r: "A", a: now, d: now + 2 }, { r: "D", a: now + 32, d: now + 33 } ] }
          ]
        }
        return {
          on: controller.crossingPassRows("test_crossing_line", { lat: 25.0, lng: 121.015 }),
          off: controller.crossingPassRows("test_crossing_line", { lat: 25.01, lng: 121.015 })
        }
      })()
    JS

    assert_equal 1, rows["on"].length
    assert_equal "1234", rows["on"].first["train_number"]
    assert_in_delta 17.0, rows["on"].first["wait"], 0.2
    assert_empty rows["off"]
  end

  test "nearby pin lists hidden lines within range and can be removed" do
    visit root_path
    assert_selector ".map-boot-overlay[hidden]", visible: :all, wait: 30

    result = page.evaluate_script(<<~JS)
      (() => {
        const el = document.querySelector('[data-controller~="map"]')
        const controller = window.Stimulus.getControllerForElementAndIdentifier(el, "map")
        const now = controller.minutesSinceMidnightFromIso(controller.simulationAt)
        const coords = { A: [ 22.0, 122.5 ], D: [ 22.0, 122.53 ] }
        controller.stationCoordForRef = (ref) => coords[ref] || null
        controller.routesManifest.other.push({ id: "test_pin_line", bbox: [ 122.5, 22.0, 122.53, 22.0 ] })
        controller.routeTracksByRouteId["test_pin_line"] = [ [ [ 122.5, 22.0 ], [ 122.53, 22.0 ] ] ]
        controller.vehicleTracksByRouteId["test_pin_line"] = [ [ [ 122.5, 22.0 ], [ 122.53, 22.0 ] ] ]
        controller.scheduleSnapshots["test_pin_line"] = {
          date: controller.simulationDateString(),
          route_id: "test_pin_line",
          trips: [
            { id: "trip:soon", train_number: "501", path: [ { r: "A", a: now, d: now + 2 }, { r: "D", a: now + 32, d: now + 33 } ] },
            { id: "trip:late", train_number: "502", path: [ { r: "A", a: now + 90, d: now + 92 }, { r: "D", a: now + 122, d: now + 123 } ] }
          ]
        }
        const near = { lat: 22.005, lng: 122.515 }
        return {
          visible: controller.layerVisible["test_pin_line"] || false,
          candidates: controller.nearbyRouteIds(near),
          far: controller.nearbyRouteIds({ lat: 22.1, lng: 122.515 }),
          rows: controller.nearbyTrainRows(near)
        }
      })()
    JS

    assert_not result["visible"]
    assert_includes result["candidates"], "test_pin_line"
    assert_not_includes result["far"], "test_pin_line"
    assert_equal [ "501" ], result["rows"].map { |row| row["train_number"] }
    assert_in_delta 556, result["rows"].first["meters"], 20

    page.execute_script(<<~JS)
      const el = document.querySelector('[data-controller~="map"]')
      const controller = window.Stimulus.getControllerForElementAndIdentifier(el, "map")
      controller.dropNearbyPin({ lat: 22.005, lng: 122.515 })
    JS
    assert_selector "[data-follow-train='501']", wait: 5
    find("[data-nearby-save]").click
    assert_equal 1, page.evaluate_script("JSON.parse(localStorage.getItem('map-nearby-pins')).length")

    find("[data-nearby-remove]").click
    assert_equal 0, page.evaluate_script("JSON.parse(localStorage.getItem('map-nearby-pins')).length")
    assert_equal 0, page.evaluate_script(<<~JS)
      window.Stimulus.getControllerForElementAndIdentifier(document.querySelector('[data-controller~="map"]'), "map").nearbyPins.length
    JS
  end

  test "metro alert banner shows operator disruptions and can be dismissed" do
    visit root_path
    assert_selector ".map-boot-overlay[hidden]", visible: :all, wait: 30

    page.execute_script(<<~JS)
      const el = document.querySelector('[data-controller~="map"]')
      const controller = window.Stimulus.getControllerForElementAndIdentifier(el, "map")
      controller.renderAlertBanner([
        { id: "TRTC:42", operator: "台北捷運", title: "淡水信義線部分區間暫停營運", message: "北投至淡水間暫停營運", url: "https://www.metro.taipei/" },
        { id: "TYMC:9", operator: "桃園捷運", title: "列車延誤", url: "javascript:alert(1)" }
      ])
    JS

    within ".map-alert-banner" do
      assert_text "台北捷運"
      assert_text "北投至淡水間暫停營運"
      assert_selector "[data-alert-id='TRTC:42'] a[href='https://www.metro.taipei/']"
      assert_no_selector "[data-alert-id='TYMC:9'] a"
      find("[data-alert-dismiss='TRTC:42']").click
      assert_no_selector "[data-alert-id='TRTC:42']"
      assert_selector "[data-alert-id='TYMC:9']"
    end
  end

  test "ride stamps need a ride to the terminal and record the distance ridden" do
    visit root_path
    assert_selector ".map-boot-overlay[hidden]", visible: :all, wait: 30

    result = page.evaluate_script(<<~JS)
      (() => {
        const el = document.querySelector('[data-controller~="map"]')
        const controller = window.Stimulus.getControllerForElementAndIdentifier(el, "map")
        localStorage.removeItem("map-ride-stamps")
        controller.followJourneyKm = (vehicle) => vehicle.km
        const path = [ { r: "A" }, { r: "B" }, { r: "C" } ]
        const ride = (id, steps) => {
          controller.followedVehicleKey = id
          steps.forEach((step) => controller.trackRideProgress({ id, route_id: "test_line", train_number: id, destination_name: "C", path, ...step }))
          return controller.completeRide()
        }
        const partial = ride("101", [ { from_station_ref: "A", to_station_ref: "B", km: 2 }, { from_station_ref: "A", to_station_ref: "B", km: 6 } ])
        const full = ride("102", [ { from_station_ref: "A", to_station_ref: "B", km: 3 }, { from_station_ref: "B", to_station_ref: "C", km: 15.26 } ])
        const duplicate = ride("102", [ { from_station_ref: "A", to_station_ref: "B", km: 3 }, { from_station_ref: "B", to_station_ref: "C", km: 15 } ])
        controller.followedVehicleKey = null
        return { partial, full, duplicate, stored: JSON.parse(localStorage.getItem("map-ride-stamps")) }
      })()
    JS

    assert_nil result["partial"]
    assert_nil result["duplicate"]
    assert_equal "102", result["full"]["train_number"]
    assert_in_delta 12.3, result["full"]["km"], 0.01
    assert_equal [ "102" ], result["stored"].map { |stamp| stamp["train_number"] }

    find(".map-explore-tools [data-tool='explore']").click
    assert_selector "[data-explore-stats]", text: "12.3"
  end

  test "relax mode toolbar toggles night tint from the simulated clock" do
    visit root_path
    assert_selector ".map-boot-overlay[hidden]", visible: :all, wait: 30

    # The playing scrubber keeps rewriting simulationAt, so check the hour rule
    # synchronously and pin the night flag for the toolbar interaction.
    nights = page.evaluate_script(<<~JS)
      (() => {
        const el = document.querySelector('[data-controller~="map"]')
        const controller = window.Stimulus.getControllerForElementAndIdentifier(el, "map")
        const original = controller.simulationAt
        const at = (iso) => { controller.simulationAt = iso; return controller.isSimulatedNight() }
        const result = [ at("2026-09-27T14:30:00Z"), at("2026-09-27T04:00:00Z"), at("2026-09-26T21:30:00Z"), at("2026-09-26T22:30:00Z") ]
        controller.simulationAt = original
        controller.randomHopTrain = () => false
        window.__relaxNight = true
        controller.isSimulatedNight = () => window.__relaxNight
        return result
      })()
    JS
    assert_equal [ true, false, true, false ], nights

    find(".map-explore-tools [data-tool='relax']").click
    assert_selector "body.map-relax-mode.map-relax-night"
    assert_selector ".map-explore-tools [data-tool='relax'].is-active"

    page.execute_script(<<~JS)
      window.__relaxNight = false
      window.Stimulus.getControllerForElementAndIdentifier(document.querySelector('[data-controller~="map"]'), "map").syncRelaxDaylight()
    JS
    assert_no_selector "body.map-relax-night"

    find(".map-explore-tools [data-tool='relax']").click
    assert_no_selector "body.map-relax-mode"
  ensure
    page.execute_script("localStorage.removeItem('map-relax-mode')")
  end

  test "group view frames every train on the followed line" do
    visit root_path
    assert_selector ".map-boot-overlay[hidden]", visible: :all, wait: 30

    result = page.evaluate_script(<<~JS)
      (() => {
        const el = document.querySelector('[data-controller~="map"]')
        const controller = window.Stimulus.getControllerForElementAndIdentifier(el, "map")
        const fake = (lat, lng, routeId) => ({ getLatLng: () => window.L.latLng(lat, lng), _vehicleData: { route_id: routeId } })
        controller.vehicleMarkersById = {
          a: fake(25.0, 121.5, "test_group"),
          b: fake(24.8, 121.0, "test_group"),
          c: fake(22.6, 120.3, "other_line")
        }
        controller.followedVehicleKey = "a"
        controller.followedRouteId = "test_group"
        controller.groupView = true
        const framed = controller.updateGroupView({ force: true })
        const bounds = controller.map.getBounds()
        controller.groupView = false
        controller.followedVehicleKey = null
        controller.vehicleMarkersById = {}
        return {
          framed,
          containsLine: bounds.contains([ 25.0, 121.5 ]) && bounds.contains([ 24.8, 121.0 ]),
          containsOther: bounds.contains([ 22.6, 120.3 ])
        }
      })()
    JS

    assert result["framed"]
    assert result["containsLine"]
    assert_not result["containsOther"]
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
    assert_selector ".out-of-station-transfer-line--passage", wait: 10, minimum: 1
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

    assert_selector ".out-of-station-transfer-line--passage", wait: 15, minimum: 2, visible: :all
  end

  test "shows out-of-station transfer link between hsr and taichung green line at HSR Taichung" do
    visit root_path
    assert_selector ".map-boot-overlay[hidden]", visible: :all, wait: 30

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
    assert_selector ".out-of-station-transfer-line--passage", wait: 15, minimum: 1, visible: :all
  end

  test "shows cross-system transfer marker at zuoying when hsr and kaohsiung red line are visible" do
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
      show("red_line")
    JS

    assert_selector ".out-of-station-transfer-line--passage", wait: 15, minimum: 1, visible: :all
    assert_selector ".leaflet-stationMarkers-pane .leaflet-interactive", wait: 15, minimum: 1, visible: :all
  end

  test "does not link hsr zuoying passage to taipei shilin R16" do
    visit root_path
    assert_selector ".map-boot-overlay[hidden]", visible: :all, wait: 30

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
      show("tamsui_xinyi")
    JS

    assert_selector ".leaflet-overlay-pane path.leaflet-interactive", wait: 20, minimum: 2

    spans = out_of_station_passage_spans
    refute island_spanning_passage?(spans), "Taipei R16 士林 must not pair with HSR 左營, got #{spans.inspect}"

    page.execute_script(<<~JS)
      const checkbox = document.getElementById("layer-red_line")
      checkbox.checked = true
      checkbox.dispatchEvent(new Event("change", { bubbles: true }))
    JS

    zuoying_span = ->(span) { span["minLat"].between?(22.5, 22.85) && span["maxLat"] < 23.2 }
    spans = wait_for_passage_spans { |current| current.any?(&zuoying_span) }
    zuoying = spans.find(&zuoying_span)
    assert zuoying, "expected a Zuoying-local HSR–紅線 passage, got #{spans.inspect}"
    refute island_spanning_passage?(spans), "Kaohsiung 紅線 R16 must not snap to 士林, got #{spans.inspect}"
  end

  test "shows co-located cross-system passage link at tainan when hsr and shalun line are visible" do
    visit root_path
    assert_selector ".map-boot-overlay[hidden]", visible: :all, wait: 30

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
      show("shalun_line")
    JS

    assert_selector ".leaflet-overlay-pane path.leaflet-interactive", wait: 20, minimum: 2
    assert_selector ".out-of-station-transfer-line--passage", wait: 15, minimum: 1, visible: :all
    assert_no_selector ".leaflet-overlay-pane .transfer-station-marker", wait: 5
  end

  test "shows walk transfer link at Hamasin when circular lrt and orange line are visible" do
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
      show("circular_lrt")
      show("orange_line")
    JS

    assert_selector ".out-of-station-transfer-line--walk-transfer", wait: 15, minimum: 1, visible: :all
    assert_no_selector ".transfer-station-marker", wait: 5
  end

  test "shows cross-system passage link at kaohsiung when tra and red line are visible" do
    visit root_path
    assert_selector ".map-boot-overlay[hidden]", visible: :all, wait: 30

    within "#taiwan-region-map" do
      assert_selector ".leaflet-tile-pane", wait: 10
    end

    page.execute_script(<<~JS)
      const show = (id) => {
        const checkbox = document.getElementById(`layer-${id}`)
        checkbox.checked = true
        checkbox.dispatchEvent(new Event("change", { bubbles: true }))
      }
      show("western_trunk_south")
      show("red_line")
    JS

    assert_selector ".leaflet-overlay-pane path.leaflet-interactive", wait: 20, minimum: 2
    assert_selector ".out-of-station-transfer-line--passage", wait: 15, minimum: 1, visible: :all
    assert_selector ".leaflet-stationMarkers-pane .leaflet-interactive", wait: 15, minimum: 1, visible: :all
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

  test "shows out-of-station transfer between wenhu line and maokong gondola at Taipei Zoo" do
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
    assert_no_selector ".leaflet-stationMarkers-pane .transfer-station-marker"
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

  test "commuter airport mrt layer shows blue line without express line" do
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
    assert_no_selector "path.airport-mrt-express-line", wait: 2
    assert_selector ".leaflet-stationMarkers-pane .leaflet-interactive", wait: 10, minimum: 1
  end

  test "express airport mrt layer shows purple line without commuter line" do
    visit root_path

    within "#taiwan-region-map" do
      assert_selector ".leaflet-tile-pane", wait: 10
    end

    page.execute_script(<<~JS)
      const checkbox = document.getElementById("layer-airport_mrt_express")
      checkbox.checked = true
      checkbox.dispatchEvent(new Event("change", { bubbles: true }))
    JS

    assert_selector "path.airport-mrt-express-line", wait: 10, minimum: 1
    assert_no_selector "path.airport-mrt-commuter-line", wait: 2
  end

  test "both airport mrt layers show parallel commuter and express lines" do
    visit root_path

    within "#taiwan-region-map" do
      assert_selector ".leaflet-tile-pane", wait: 10
    end

    page.execute_script(<<~JS)
      ;["airport_mrt", "airport_mrt_express"].forEach((id) => {
        const checkbox = document.getElementById(`layer-${id}`)
        checkbox.checked = true
        checkbox.dispatchEvent(new Event("change", { bubbles: true }))
      })
    JS

    assert_selector "path.airport-mrt-commuter-line", wait: 10, minimum: 1
    assert_selector "path.airport-mrt-express-line", wait: 10, minimum: 1
    assert_selector ".transfer-station-marker", wait: 10, minimum: 1
  end

  test "airport mrt layer toggle uses commuter blue" do
    visit root_path

    row = find(".route-search-item[data-route-id='airport_mrt']", visible: :all)
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
    assert names.any? { |name| name.include?("第二航廈（南側）") },
           "expected south skytrain stop with optional 停駛 suffix, got #{names.inspect}"
  end

  test "airport mrt express layer toggle uses purple line color" do
    visit root_path

    row = find(".route-search-item[data-route-id='airport_mrt_express']", visible: :all)
    dot = row.find("span[style*='background-color']", match: :first, visible: :all)
    assert_match(/rgb\(106,\s*44,\s*145\)/i, dot[:style])
  end

  test "airport mrt commuter route page lists commuter section only" do
    visit route_path("airport_mrt")
    assert_selector ".route-stop-item", minimum: 7, wait: 10

    assert_selector ".route-stops-section-heading", text: "普通車"
    assert_no_selector ".route-stops-section-heading", text: "直達車"

    refs = page.all(".route-stop-item__index", minimum: 7, wait: 10).map(&:text)
    assert_equal "A1", refs.first
    assert_includes refs, "A21"
    assert refs.length > 7, "expected full commuter stop list, got #{refs.length} stops"
  end

  test "airport mrt express route page lists express section only" do
    visit route_path("airport_mrt_express")
    assert_selector ".route-stop-item", minimum: 7, wait: 10

    assert_selector ".route-stops-section-heading", text: "直達車"
    assert_no_selector ".route-stops-section-heading", text: "普通車"

    express_heading = find(".route-stops-section-heading", text: "直達車")
    express_section_refs = express_heading.all(
      :xpath,
      "./following-sibling::li[./button[contains(@class, 'route-stop-item')]]"
    ).map { |item| item.find(".route-stop-item__index").text }

    assert_equal %w[A1 A3 A8 A12 A13 A18 A21], express_section_refs
  end

  test "danhai lrt layer toggle uses coral line color" do
    visit root_path

    row = find(".route-search-item[data-route-id='danhai_lrt']", visible: :all)
    dot = row.find("span[style*='background-color']", match: :first, visible: :all)
    assert_match(/rgb\(237,\s*107,\s*70\)/i, dot[:style])
  end

  test "airport mrt map shows blue commuter and purple express solid lines" do
    visit root_path

    within "#taiwan-region-map" do
      assert_selector ".leaflet-tile-pane", wait: 10
    end

    page.execute_script(<<~JS)
      ;["airport_mrt", "airport_mrt_express"].forEach((id) => {
        const checkbox = document.getElementById(`layer-${id}`)
        checkbox.checked = true
        checkbox.dispatchEvent(new Event("change", { bubbles: true }))
      })
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
    transfer_z = page.evaluate_script("document.querySelector('.leaflet-outOfStationTransfers-pane')?.style.zIndex")
    station_z = page.evaluate_script("document.querySelector('.leaflet-stationMarkers-pane')?.style.zIndex")
    assert commuter_z.present? && express_z.present? && transfer_z.present? && station_z.present?
    assert commuter_z.to_i > express_z.to_i, "expected commuter pane (z=#{commuter_z}) above express pane (z=#{express_z})"
    assert transfer_z.to_i > commuter_z.to_i, "expected transfer pane (z=#{transfer_z}) above commuter pane (z=#{commuter_z})"
    assert station_z.to_i > transfer_z.to_i, "expected station pane (z=#{station_z}) above transfer pane (z=#{transfer_z})"
    assert station_z.to_i > commuter_z.to_i, "expected station pane (z=#{station_z}) above commuter pane (z=#{commuter_z})"
  end

  test "airport mrt express line renders as solid purple" do
    visit root_path

    within "#taiwan-region-map" do
      assert_selector ".leaflet-tile-pane", wait: 10
    end

    page.execute_script(<<~JS)
      const checkbox = document.getElementById("layer-airport_mrt_express")
      checkbox.checked = true
      checkbox.dispatchEvent(new Event("change", { bubbles: true }))
    JS

    express_path = find("path.airport-mrt-express-line", wait: 10, match: :first)
    dash = express_path[:style].to_s[/stroke-dasharray:\s*([^;]+)/i, 1]
    assert dash.blank?, "expected solid express line, got dasharray: #{dash}"
  end

  test "sidebar collapse button hides and restores the layers panel on desktop" do
    visit root_path
    assert_selector ".map-boot-overlay[hidden]", visible: :all, wait: 30
    assert_selector "#map-layers-panel-body", visible: :visible

    toggle = find(".map-ui-panel__toggle[aria-controls='map-layers-panel-body']", visible: :all)
    toggle.click
    assert_selector ".map-split-layout--sidebar-collapsed", wait: 5
    assert_selector "#map-layers-panel-body", visible: :hidden
    assert_selector ".map-ui-panel__toggle[aria-expanded='false']", visible: :all

    # The toggle slides with the collapsing sidebar; a pointer click mid-transition can miss it.
    page.execute_script("document.querySelector(\".map-ui-panel__toggle[aria-controls='map-layers-panel-body']\").click()")
    assert_no_selector ".map-split-layout--sidebar-collapsed", wait: 5
    assert_selector "#map-layers-panel-body", visible: :visible
    assert_selector ".map-ui-panel__toggle[aria-expanded='true']", visible: :all
  end

  private

    def wait_for_passage_spans(timeout: 15)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
      loop do
        spans = out_of_station_passage_spans
        return spans if yield(spans) || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

        sleep 0.2
      end
    end

    def out_of_station_passage_spans
      page.evaluate_script(<<~JS)
        (() => {
          const el = document.querySelector('[data-controller~="map"]')
          const controller = window.Stimulus.getControllerForElementAndIdentifier(el, "map")
          const group = controller?.outOfStationTransferGroup
          if (!group) return []

          const spans = []
          group.eachLayer((layer) => {
            const className = layer.options?.className || ""
            if (!className.includes("out-of-station-transfer-line--passage")) return

            const points = (layer.getLatLngs?.() || [])
              .flat(Infinity)
              .filter((point) => point && typeof point.lat === "number")
            if (points.length < 2) return

            const lats = points.map((point) => point.lat)
            const lngs = points.map((point) => point.lng)
            spans.push({
              minLat: Math.min(...lats),
              maxLat: Math.max(...lats),
              minLng: Math.min(...lngs),
              maxLng: Math.max(...lngs)
            })
          })
          return spans
        })()
      JS
    end

    def island_spanning_passage?(spans)
      Array(spans).any? { |span| span["minLat"] < 23.5 && span["maxLat"] > 24.5 }
    end
end
