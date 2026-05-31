// airport-mrt-colors-v3: commuter #0073B7, express #6A2C91, solid parallel tracks
import { Controller } from "@hotwired/stimulus"

const LEAFLET_BOUNDS = [ [ 21.85, 118.15 ], [ 26.45, 122.25 ] ]

const BASE_LAYERS = [ "bus", "train", "hsr", "ferry" ]

const LAYER_COLORS = {
  bus: "#2563eb",
  train: "#dc2626",
  hsr: "#9333ea",
  ferry: "#0891b2",
}

const MAX_SNAP_DISTANCE_METERS = 350

const AIRPORT_MRT_COMMUTER_COLOR = "#0073B7"
const AIRPORT_MRT_BRAND_COLOR = "#6A2C91"
const EXPRESS_LINE_COLOR = AIRPORT_MRT_BRAND_COLOR
const AIRPORT_MRT_EXPRESS_STOP_REFS = new Set([ "A1", "A3", "A8", "A12", "A13", "A18", "A21" ])
const DANHAI_LRT_COLOR = "#ED6B46"
const DANHAI_SHARED_STATION_REFS = new Set(
  Array.from({ length: 9 }, (_, index) => `V${String(index + 1).padStart(2, "0")}`)
)
const DANHAI_LANHAI_STATION_ORDER = [ "V28", "V27", "V26" ]
const DANHAI_SHARED_ORIGIN_REF = "V01"
const DANHAI_LUSHAN_DESTINATION_REF = "V11"
const DANHAI_LANHAI_DESTINATION_REF = "V26"
const OUT_OF_STATION_MARKER_COLOR = "#737373"
const TRANSFER_LINE_COLOR = "#525252"
const TRANSFER_LINE_COLOR_FARE_DISCOUNT = "#3a3a3a"
const FARE_DISCOUNT_TRACK_OFFSET_METERS = 7
const TRANSFER_LINE_WEIGHT = 5
const FARE_DISCOUNT_LINE_OFFSET_METERS = 3.5
const PARALLEL_TRACK_HALF_OFFSET_PX = 6
const PARALLEL_TRACK_ROUTE_IDS = new Set([ "airport_mrt", "airport_mrt_express", "danhai_lrt" ])
const LOOP_LINE_ROUTE_IDS = new Set([ "circular_lrt" ])

const METRO_SYSTEM_IDS = [
  "taipei_metro",
  "new_taipei_metro",
  "taoyuan_metro",
  "taichung_metro",
  "kaohsiung_metro"
]

export default class extends Controller {
  static targets = [
    "map",
    "layerCheckbox",
    "layersPanel",
    "legendPanel",
    "layerSearchInput",
    "layerSearchItem",
    "layerSearchGroup",
    "layerSearchEmpty",
    "layerSearchMuted",
    "layerSearchClear"
  ]

  connect() {
    if (this.map) return

    this.layerGroups = {}
    this.layerVisible = {}
    this.layerLoadGeneration = {}
    this.geoJSONCache = {}
    this.geoJSONDataByUrl = {}
    this.routesManifest = {}
    this.lineColorsByPrefix = {}
    this.routesByLineRef = {}
    this.routeTracksByRouteId = {}
    this.branchesByMain = {}
    this.outOfStationTransfers = []
    this.outOfStationEndpointKeys = new Set()
    this.transferKindByEndpointKey = new Map()
    this.metroDepots = []
    this.stationCoordinatesByKey = {}
    this.mapReady = false
    this.themeObserver = null
    this.setLayerControlsDisabled(true)
    this.waitForLeaflet(0)
  }

  disconnect() {
    if (this.resizeHandler) window.removeEventListener("resize", this.resizeHandler)
    if (this.parallelTracksRefreshTimer) clearTimeout(this.parallelTracksRefreshTimer)
    if (this.map && this.refreshParallelTracksOnZoom) {
      this.map.off("zoomend", this.refreshParallelTracksOnZoom)
    }
    this.themeObserver?.disconnect()
    this.themeObserver = null
    this.map?.remove()
    this.map = null
    this.mapReady = false
    this.layerGroups = {}
    this.layerVisible = {}
    this.layerLoadGeneration = {}
    this.geoJSONCache = {}
    this.geoJSONDataByUrl = {}
    this.routesManifest = {}
    this.lineColorsByPrefix = {}
    this.routesByLineRef = {}
    this.routeTracksByRouteId = {}
    this.branchesByMain = {}
    this.outOfStationTransfers = []
    this.outOfStationEndpointKeys = new Set()
    this.transferKindByEndpointKey = new Map()
    this.metroDepots = []
    this.stationCoordinatesByKey = {}
  }

  waitForLeaflet(attempts) {
    if (window.L) {
      this.initMap()
      return
    }

    if (attempts > 60) {
      this.element.innerHTML = "<p style=\"padding:1rem;font-family:sans-serif\">Map failed to load. Hard-refresh the page.</p>"
      return
    }

    setTimeout(() => this.waitForLeaflet(attempts + 1), 50)
  }

  async initMap() {
    const L = window.L
    const mapElement = this.hasMapTarget ? this.mapTarget : this.element

    this.map = L.map(mapElement, {
      zoomControl: true,
      scrollWheelZoom: true,
      dragging: true,
      touchZoom: true
    })

    this.tileLayer = L.tileLayer(this.basemapUrl(), {
      subdomains: "abcd",
      maxZoom: 20,
      attribution: "&copy; OpenStreetMap &copy; CARTO"
    }).addTo(this.map)

    this.watchThemeChanges()

    await Promise.all([
      this.loadRoutesManifest(),
      this.loadOutOfStationTransfers(),
      this.loadMetroDepots()
    ])

    const transferPane = this.map.createPane("outOfStationTransfers")
    transferPane.style.zIndex = 650
    this.outOfStationTransferPane = "outOfStationTransfers"

    const expressPane = this.map.createPane("expressRoutes")
    expressPane.style.zIndex = 610
    this.expressRoutePane = "expressRoutes"

    const commuterPane = this.map.createPane("commuterRoutes")
    commuterPane.style.zIndex = 630
    this.commuterRoutePane = "commuterRoutes"

    const stationPane = this.map.createPane("stationMarkers")
    stationPane.style.zIndex = 640
    this.stationMarkerPane = "stationMarkers"

    this.outOfStationTransferGroup = L.featureGroup().addTo(this.map)
    this.inStationTransferGroup = L.featureGroup().addTo(this.map)
    this.metroDepotGroup = L.featureGroup().addTo(this.map)

    this.allLayerIds().forEach((layerId) => {
      this.layerGroups[layerId] = L.featureGroup()
      this.layerVisible[layerId] = false
      this.layerLoadGeneration[layerId] = 0
    })

    this.map.fitBounds(LEAFLET_BOUNDS)
    this.map.zoomControl.setPosition("topright")
    this.refreshParallelTracksOnZoom = () => this.scheduleParallelTracksRefresh()
    this.map.on("zoomend", this.refreshParallelTracksOnZoom)

    this.resizeHandler = () => this.map?.invalidateSize(true)
    requestAnimationFrame(this.resizeHandler)
    setTimeout(this.resizeHandler, 100)
    setTimeout(this.resizeHandler, 500)
    window.addEventListener("resize", this.resizeHandler)

    this.mapReady = true
    this.setLayerControlsDisabled(false)
    this.syncPanelToggleStates()
  }

  allLayerIds() {
    return [ ...BASE_LAYERS, ...this.routeLayerIds() ]
  }

  routeLayerIds() {
    const ids = []

    Object.values(this.routesManifest).forEach((routes) => {
      if (!Array.isArray(routes)) return

      routes.forEach((route) => {
        if (route.id && !route.branch_of) ids.push(route.id)
      })
    })

    return ids
  }

  findRoute(layerId) {
    for (const routes of Object.values(this.routesManifest)) {
      if (!Array.isArray(routes)) continue

      const route = routes.find((entry) => entry.id === layerId)
      if (route) return route
    }

    return null
  }

  async loadOutOfStationTransfers() {
    try {
      const response = await fetch("/geojson/out_of_station_transfers.json", { cache: "no-store" })
      if (!response.ok) throw new Error("out-of-station transfers missing")

      this.outOfStationTransfers = await response.json()
      this.outOfStationEndpointKeys = this.buildOutOfStationEndpointKeys(this.outOfStationTransfers)
      this.transferKindByEndpointKey = this.buildTransferKindByEndpointKey(this.outOfStationTransfers)
    } catch (error) {
      console.error("Failed to load out-of-station transfers", error)
      this.outOfStationTransfers = []
      this.outOfStationEndpointKeys = new Set()
      this.transferKindByEndpointKey = new Map()
    }
  }

  buildOutOfStationEndpointKeys(transfers) {
    const keys = new Set()

    transfers.forEach((transfer) => {
      transfer.endpoints?.forEach((endpoint) => {
        if (!endpoint.route_id || !endpoint.ref) return

        this.transferStationRefs(endpoint.ref).forEach((stationRef) => {
          keys.add(this.stationKey(endpoint.route_id, stationRef))
        })
      })
    })

    return keys
  }

  buildTransferKindByEndpointKey(transfers) {
    const kindByKey = new Map()

    transfers.forEach((transfer) => {
      const kind = this.transferKind(transfer)
      transfer.endpoints?.forEach((endpoint) => {
        if (!endpoint.route_id || !endpoint.ref) return

        this.transferStationRefs(endpoint.ref).forEach((stationRef) => {
          kindByKey.set(this.stationKey(endpoint.route_id, stationRef), kind)
        })
      })
    })

    return kindByKey
  }

  transferKind(transfer) {
    return transfer?.kind === "passage" ? "passage" : "fare_discount"
  }

  transferNoteForKind(kind) {
    if (kind === "passage") return "聯通道轉乘"
    return "站外轉乘（優惠）"
  }

  async loadMetroDepots() {
    try {
      const response = await fetch("/geojson/metro_depots.json", { cache: "no-store" })
      if (!response.ok) throw new Error("metro depots missing")

      this.metroDepots = await response.json()
    } catch (error) {
      console.error("Failed to load metro depots", error)
      this.metroDepots = []
    }
  }

  async loadRoutesManifest() {
    try {
      const response = await fetch("/geojson/routes.json")
      if (!response.ok) throw new Error("routes manifest missing")
      this.routesManifest = await response.json()
      const { colorsByPrefix, routesByLineRef } = this.buildLineColorMap()
      this.lineColorsByPrefix = colorsByPrefix
      this.routesByLineRef = routesByLineRef
      this.branchesByMain = this.buildBranchesByMain()
    } catch (error) {
      console.error("Failed to load routes manifest", error)
      this.routesManifest = {}
      this.lineColorsByPrefix = {}
      this.routesByLineRef = {}
      this.branchesByMain = {}
    }
  }

  buildBranchesByMain() {
    const branchesByMain = {}

    Object.values(this.routesManifest).forEach((routes) => {
      if (!Array.isArray(routes)) return

      routes.forEach((route) => {
        if (!route.branch_of) return

        if (!branchesByMain[route.branch_of]) branchesByMain[route.branch_of] = []
        branchesByMain[route.branch_of].push(route)
      })
    })

    return branchesByMain
  }

  routesToLoad(layerId) {
    const route = this.findRoute(layerId)
    if (!route) return []

    return [ route, ...(this.branchesByMain[layerId] || []) ]
  }

  buildLineColorMap() {
    const colorsByPrefix = {}
    const routesByLineRef = {}

    Object.values(this.routesManifest).forEach((routes) => {
      if (!Array.isArray(routes)) return

      routes.forEach((route) => {
        if (!route.ref) return

        if (!routesByLineRef[route.ref]) routesByLineRef[route.ref] = []
        routesByLineRef[route.ref].push(route)

        if (!route.branch_of) colorsByPrefix[route.ref] = this.routeDisplayColor(route) || route.color
      })
    })

    return { colorsByPrefix, routesByLineRef }
  }

  async resetView() {
    await this.showAllMetro()
  }

  async showAllMetro() {
    if (!this.mapReady || !this.map) return

    await this.setAllMetroLayersVisible(true, { fitBounds: true })
  }

  resetViewport() {
    if (!this.mapReady || !this.map) return

    this.map.fitBounds(LEAFLET_BOUNDS)
  }

  toggleLayersPanel() {
    if (!this.hasLayersPanelTarget) return

    this.layersPanelTarget.classList.toggle("map-ui-panel--collapsed")
    this.syncPanelToggleState(this.layersPanelTarget)
  }

  toggleLegendPanel() {
    if (!this.hasLegendPanelTarget) return

    this.legendPanelTarget.classList.toggle("map-ui-panel--collapsed")
    this.syncPanelToggleState(this.legendPanelTarget)
  }

  syncPanelToggleState(panel) {
    const button = panel?.querySelector(".map-ui-panel__toggle")
    if (!button) return

    const collapsed = panel.classList.contains("map-ui-panel--collapsed")
    const isLegend = panel === this.legendPanelTarget
    const label = isLegend
      ? (collapsed ? "展開圖例" : "收合圖例")
      : (collapsed ? "展開圖層面板" : "收合圖層面板")

    button.setAttribute("aria-expanded", (!collapsed).toString())
    button.setAttribute("aria-label", label)
  }

  syncPanelToggleStates() {
    if (this.hasLayersPanelTarget) this.syncPanelToggleState(this.layersPanelTarget)
    if (this.hasLegendPanelTarget) this.syncPanelToggleState(this.legendPanelTarget)
  }

  filterLayers() {
    if (!this.hasLayerSearchInputTarget) return

    const query = this.normalizeSearchQuery(this.layerSearchInputTarget.value)
    const hasQuery = query.length > 0
    let visibleItemCount = 0

    this.layerSearchItemTargets.forEach((item) => {
      const text = this.normalizeSearchQuery(item.dataset.searchText || "")
      const match = !hasQuery || text.includes(query)

      item.classList.toggle("hidden", !match)
      if (match) visibleItemCount += 1
    })

    this.layerSearchGroupTargets.forEach((group) => {
      const groupText = this.normalizeSearchQuery(group.dataset.searchText || "")
      const groupMatch = hasQuery && groupText.includes(query)
      const childMatch = hasQuery && Array.from(
        group.querySelectorAll("[data-map-target=\"layerSearchItem\"]")
      ).some((item) => !item.classList.contains("hidden"))
      const visible = !hasQuery || groupMatch || childMatch

      group.classList.toggle("hidden", !visible)

      if (hasQuery && (groupMatch || childMatch)) this.openLayerSearchGroup(group)
    })

    if (this.hasLayerSearchMutedTarget) {
      this.layerSearchMutedTargets.forEach((element) => {
        element.classList.toggle("hidden", hasQuery)
      })
    }

    if (this.hasLayerSearchClearTarget) {
      this.layerSearchClearTarget.classList.toggle("hidden", !hasQuery)
    }

    if (this.hasLayerSearchEmptyTarget) {
      const showEmpty = hasQuery && visibleItemCount === 0 &&
        this.layerSearchGroupTargets.every((group) => group.classList.contains("hidden"))

      this.layerSearchEmptyTarget.classList.toggle("hidden", !showEmpty)
    }
  }

  clearLayerSearch() {
    if (!this.hasLayerSearchInputTarget) return

    this.layerSearchInputTarget.value = ""
    this.filterLayers()
    this.layerSearchInputTarget.focus()
  }

  normalizeSearchQuery(value) {
    return value.trim().toLowerCase().replace(/\s+/g, " ")
  }

  openLayerSearchGroup(group) {
    const collapsible = group.querySelector("[data-controller~=\"ruby-ui--collapsible\"]")
    if (!collapsible) return

    const controller = this.application.getControllerForElementAndIdentifier(
      collapsible,
      "ruby-ui--collapsible"
    )

    controller?.open()
  }

  basemapUrl() {
    const dark = document.documentElement.classList.contains("dark")

    return dark
      ? "https://{s}.basemaps.cartocdn.com/dark_nolabels/{z}/{x}/{y}{r}.png"
      : "https://{s}.basemaps.cartocdn.com/light_nolabels/{z}/{x}/{y}{r}.png"
  }

  applyThemeBasemap() {
    if (!this.tileLayer) return

    this.tileLayer.setUrl(this.basemapUrl())
  }

  watchThemeChanges() {
    this.applyThemeBasemap()

    this.themeObserver = new MutationObserver(() => this.applyThemeBasemap())
    this.themeObserver.observe(document.documentElement, {
      attributes: true,
      attributeFilter: [ "class" ]
    })
  }

  async setAllMetroLayersVisible(visible, { fitBounds = false } = {}) {
    const routeIds = this.allMetroRouteIds()
    if (routeIds.length === 0) {
      if (!visible) this.map?.fitBounds(LEAFLET_BOUNDS)
      return
    }

    const allMetroCheckbox = this.checkboxForLayer("all_metro")
    if (allMetroCheckbox) allMetroCheckbox.checked = visible

    this.setLayerControlsDisabled(true)

    try {
      if (visible) {
        for (const routeId of routeIds) {
          await this.showLayer(routeId, { fitBounds: false })
        }

        METRO_SYSTEM_IDS.forEach((systemId) => this.syncMetroSystemCheckbox(systemId))
        this.syncAllMetroCheckbox()

        if (fitBounds) {
          this.fitVisibleRouteBounds()
        }
      } else {
        routeIds.forEach((routeId) => {
          this.hideLayerWithCheckbox(routeId, this.checkboxForLayer(routeId))
        })

        METRO_SYSTEM_IDS.forEach((systemId) => this.syncMetroSystemCheckbox(systemId))
        if (allMetroCheckbox) allMetroCheckbox.checked = false
      }

      this.updateOutOfStationTransfers()
    } finally {
      this.setLayerControlsDisabled(false)
    }
  }

  setLayerControlsDisabled(disabled) {
    this.layerCheckboxTargets.forEach((checkbox) => {
      if (checkbox.dataset.available === "false") {
        checkbox.disabled = true
        return
      }

      checkbox.disabled = disabled
    })
  }

  checkboxForLayer(layerId) {
    return document.getElementById(`layer-${layerId}`)
  }

  mainRouteIdsForSystem(systemId) {
    return (this.routesManifest[systemId] || [])
      .filter((route) => route.id && !route.branch_of)
      .map((route) => route.id)
  }

  allMetroRouteIds() {
    const ids = []

    METRO_SYSTEM_IDS.forEach((systemId) => {
      ids.push(...this.mainRouteIdsForSystem(systemId))
    })

    return ids
  }

  metroSystemForRoute(routeId) {
    for (const systemId of METRO_SYSTEM_IDS) {
      if (this.mainRouteIdsForSystem(systemId).includes(routeId)) return systemId
    }

    return null
  }

  syncMetroSystemCheckbox(systemId) {
    const checkbox = this.checkboxForLayer(systemId)
    if (!checkbox) return

    const routeIds = this.mainRouteIdsForSystem(systemId)
    if (routeIds.length === 0) return

    const allOn = routeIds.every((routeId) => this.layerVisible[routeId])
    const anyOn = routeIds.some((routeId) => this.layerVisible[routeId])

    checkbox.checked = allOn
    checkbox.indeterminate = anyOn && !allOn
  }

  syncAllMetroCheckbox() {
    const checkbox = this.checkboxForLayer("all_metro")
    if (!checkbox) return

    const routeIds = this.allMetroRouteIds()
    if (routeIds.length === 0) return

    const allOn = routeIds.every((routeId) => this.layerVisible[routeId])
    const anyOn = routeIds.some((routeId) => this.layerVisible[routeId])

    checkbox.checked = allOn
    checkbox.indeterminate = anyOn && !allOn
  }

  async toggleMetroSystem(event) {
    event.preventDefault()

    const checkbox = event.currentTarget
    const systemId = event.params.metroSystem
    const visible = checkbox.checked

    if (!this.mapReady || !this.map) {
      checkbox.checked = false
      return
    }

    const routeIds = this.mainRouteIdsForSystem(systemId)
    if (routeIds.length === 0) {
      checkbox.checked = false
      return
    }

    this.setLayerControlsDisabled(true)

    try {
      if (visible) {
        for (const routeId of routeIds) {
          await this.showLayer(routeId, { fitBounds: false })
        }

        this.fitVisibleRouteBounds()
      } else {
        routeIds.forEach((routeId) => {
          this.hideLayerWithCheckbox(routeId, this.checkboxForLayer(routeId))
        })
      }

      this.syncMetroSystemCheckbox(systemId)
      this.syncAllMetroCheckbox()
      this.updateOutOfStationTransfers()
    } finally {
      this.setLayerControlsDisabled(false)
    }
  }

  async toggleAllMetro(event) {
    event.preventDefault()

    const checkbox = event.currentTarget
    const visible = checkbox.checked

    if (!this.mapReady || !this.map) {
      checkbox.checked = false
      return
    }

    if (this.allMetroRouteIds().length === 0) {
      checkbox.checked = false
      return
    }

    await this.setAllMetroLayersVisible(visible, { fitBounds: visible })
  }

  indexStationCoordinates(routeId, data) {
    const L = window.L

    ;(data.features || []).forEach((feature) => {
      if (feature.properties?.feature_type !== "station") return

      const ref = feature.properties.ref
      const coordinates = feature.geometry?.coordinates
      if (!ref || !coordinates) return

      const latlng = L.latLng(coordinates[1], coordinates[0])

      this.transferStationRefs(ref).forEach((stationRef) => {
        this.stationCoordinatesByKey[this.stationKey(routeId, stationRef)] = latlng
      })
    })
  }

  reindexVisibleStationCoordinates() {
    this.visibleRouteLayerIds().forEach((layerId) => {
      this.routesToLoad(layerId).forEach((route) => {
      const file = route.file || route.url
      const data = file ? this.geoJSONDataByUrl[file] : null
      if (data) this.indexStationCoordinates(route.id, this.displayGeoJSON(data, route))
      })
    })
  }

  clearStationCoordinatesForRoutes(routes) {
    routes.forEach((route) => {
      const file = route.file || route.url
      const data = file ? this.geoJSONDataByUrl[file] : null
      if (!data) return

      ;(data.features || []).forEach((feature) => {
        if (feature.properties?.feature_type !== "station") return

        this.transferStationRefs(feature.properties?.ref).forEach((stationRef) => {
          delete this.stationCoordinatesByKey[this.stationKey(route.id, stationRef)]
        })
      })
    })
  }

  latLngFromStationFeature(feature) {
    const coordinates = feature.geometry?.coordinates
    if (!coordinates) return null

    return window.L.latLng(coordinates[1], coordinates[0])
  }

  stationLatLngFromCachedRoute(routeId, ref) {
    const route = this.findRoute(routeId)
    const file = route?.file || route?.url
    const data = file ? this.geoJSONDataByUrl[file] : null
    if (!data) return null

    const displayData = this.displayGeoJSON(data, route)

    for (const feature of displayData.features || []) {
      if (feature.properties?.feature_type !== "station") continue

      const stationRefs = this.transferStationRefs(feature.properties?.ref)
      if (!stationRefs.includes(ref)) continue

      return this.latLngFromStationFeature(feature)
    }

    return null
  }

  stationKey(routeId, ref) {
    return `${routeId}:${ref}`
  }

  stationLatLng(routeId, ref) {
    if (!routeId || !ref) return null

    const direct = this.stationCoordinatesByKey[this.stationKey(routeId, ref)]
    if (direct) return direct

    for (const stationRef of this.transferStationRefs(ref)) {
      const latlng = this.stationCoordinatesByKey[this.stationKey(routeId, stationRef)]
      if (latlng) return latlng
    }

    return this.stationLatLngFromCachedRoute(routeId, ref)
  }

  updateOutOfStationTransfers() {
    const L = window.L
    const group = this.outOfStationTransferGroup

    if (!group || !this.map) return

    this.reindexVisibleStationCoordinates()
    group.clearLayers()

    this.outOfStationTransfers.forEach((transfer) => {
      if (!transfer.routes?.every((routeId) => this.layerVisible[routeId])) return

      const latlngs = transfer.endpoints
        .map((endpoint) => this.stationLatLng(endpoint.route_id, endpoint.ref))
        .filter(Boolean)

      if (latlngs.length < 2) return

      const kind = this.transferKind(transfer)
      const layers = this.transferConnectionLayers(latlngs, kind)

      layers.forEach((layer) => {
        if (transfer.label) {
          layer.bindPopup(this.transferPopupHtml(transfer.label, kind))
        }
        group.addLayer(layer)
      })
    })

    if (group.getLayers().length > 0) {
      if (!this.map.hasLayer(group)) group.addTo(this.map)
      group.bringToFront()
    } else if (this.map.hasLayer(group)) {
      this.map.removeLayer(group)
    }

    this.updateInStationTransferMarkers()
    this.updateMetroDepots()
  }

  updateMetroDepots() {
    const L = window.L
    const group = this.metroDepotGroup

    if (!group || !this.map) return

    group.clearLayers()

    this.metroDepots.forEach((depot) => {
      if (depot.lon == null || depot.lat == null) return
      if (!depot.routes?.some((routeId) => this.layerVisible[routeId])) return

      const color = this.depotDisplayColor(depot) || "#64748B"
      const raw = L.latLng(depot.lat, depot.lon)
      const snapped = this.snapDepotToVisibleTracks(raw, depot)
      const marker = this.metroDepotMarkerAt(snapped, color)

      const gradeNote = depot.grade ? `<br><span style="opacity:0.8">${depot.grade}機廠</span>` : ""
      const routeNames = this.depotRouteNames(depot)
      const routeNote = routeNames.length > 0 ? `<br><span style="opacity:0.8">服務路線：${routeNames.join("、")}</span>` : ""

      marker.bindPopup(
        `<strong>${depot.name}</strong>${gradeNote}${routeNote}<br><span style="opacity:0.8">車輛基地（不提供載客）</span>`
      )

      group.addLayer(marker)
    })

    if (group.getLayers().length > 0) {
      if (!this.map.hasLayer(group)) group.addTo(this.map)
      group.bringToFront()
    } else if (this.map.hasLayer(group)) {
      this.map.removeLayer(group)
    }
  }

  snapDepotToVisibleTracks(latlng, depot) {
    if (!latlng) return latlng

    const candidates = (depot?.routes || []).filter(Boolean)
    if (candidates.length === 0) return latlng

    const visible = candidates.filter((routeId) => this.layerVisible[routeId])
    const ordered = [ ...visible, ...candidates.filter((routeId) => !visible.includes(routeId)) ]

    let best = latlng
    let bestDistance = Infinity

    ordered.forEach((routeId) => {
      const snapped = this.snapToRouteTracksForDepot(latlng, routeId)
      const distance = latlng.distanceTo(snapped)

      if (distance < bestDistance) {
        bestDistance = distance
        best = snapped
      }
    })

    return best
  }

  snapToRouteTracksForDepot(latlng, routeId) {
    const lines = this.routeTracksByRouteId[routeId] || []
    if (lines.length === 0) return latlng

    return this.nearestPointOnLines(latlng, lines)
  }

  depotDisplayColor(depot) {
    for (const routeId of depot.routes || []) {
      if (!this.layerVisible[routeId]) continue
      const color = this.routeDisplayColor(this.findRoute(routeId))
      if (color) return color
    }

    for (const routeId of depot.routes || []) {
      const color = this.routeDisplayColor(this.findRoute(routeId))
      if (color) return color
    }

    return null
  }

  depotRouteNames(depot) {
    return (depot.routes || [])
      .map((routeId) => this.findRoute(routeId)?.name)
      .filter(Boolean)
  }

  metroDepotMarkerAt(latlng, color) {
    const L = window.L
    const safeColor = color || "#64748B"
    const html = `<div class="metro-depot-marker" aria-hidden="true" style="--depot-color:${safeColor}"></div>`

    return L.marker(latlng, {
      icon: L.divIcon({
        className: "metro-depot-icon",
        html,
        iconSize: [ 16, 16 ],
        iconAnchor: [ 8, 8 ]
      }),
      pane: this.stationMarkerPane,
      zIndexOffset: 430
    })
  }

  isInStationTransferRef(ref) {
    return this.transferStationRefs(ref).length > 1
  }

  hiddenStationMarker(latlng) {
    const L = window.L

    return L.circleMarker(latlng, {
      radius: 0,
      opacity: 0,
      fillOpacity: 0,
      interactive: false,
      pane: this.stationMarkerPane
    })
  }

  updateInStationTransferMarkers() {
    const L = window.L
    const group = this.inStationTransferGroup

    if (!group || !this.map) return

    group.clearLayers()

    const transfersByKey = new Map()

    this.visibleRouteLayerIds().forEach((layerId) => {
      this.routesToLoad(layerId).forEach((route) => {
        if (!this.layerVisible[route.id]) return

        const file = route.file || route.url
        const data = file ? this.geoJSONDataByUrl[file] : null
        if (!data) return

        const displayData = this.displayGeoJSON(data, route)

        ;(displayData.features || []).forEach((feature) => {
          if (feature.properties?.feature_type !== "station") return

          const ref = feature.properties?.ref
          if (!this.isInStationTransferRef(ref)) return

          const key = this.transferStationRefs(ref).slice().sort().join(";")
          if (!transfersByKey.has(key)) transfersByKey.set(key, feature)
        })
      })
    })

    transfersByKey.forEach((feature) => {
      const ref = feature.properties?.ref
      const name = feature.properties?.name
      const stationRefs = this.transferStationRefs(ref)
      const coordinates = feature.geometry?.coordinates
      if (!coordinates) return

      const latlng = L.latLng(coordinates[1], coordinates[0])
      const lineColors = stationRefs
        .map((stationRef) => this.colorForStationRef(stationRef) || feature.properties?.color)
        .slice(0, 2)
      const snapPrefix = this.linePrefixForStationRef(stationRefs[0])
      const position = this.snapToTracks(latlng, snapPrefix)
      const marker = this.transferStationMarkerAt(position, lineColors)
      const label = ref ? `${ref} ${name}` : name

      marker.bindPopup(`<strong>${label}</strong><br><span style="opacity:0.8">站內轉乘</span>`)
      group.addLayer(marker)
    })

    if (group.getLayers().length > 0) {
      if (!this.map.hasLayer(group)) group.addTo(this.map)
      group.bringToFront()
    } else if (this.map.hasLayer(group)) {
      this.map.removeLayer(group)
    }
  }

  fitVisibleRouteBounds() {
    if (!this.map) return

    const L = window.L
    const combined = L.featureGroup()

    this.visibleRouteLayerIds().forEach((layerId) => {
      const group = this.layerGroups[layerId]
      if (group && group.getLayers().length > 0) {
        combined.addLayer(group)
      }
    })

    if (combined.getLayers().length === 0) return

    try {
      const bounds = combined.getBounds()
      if (bounds.isValid()) {
        this.map.fitBounds(bounds.pad(0.1))
      }
    } catch (error) {
      console.warn("Could not fit bounds for visible routes", error)
    }
  }

  bumpLayerGeneration(layerId) {
    this.layerLoadGeneration[layerId] = (this.layerLoadGeneration[layerId] || 0) + 1
    return this.layerLoadGeneration[layerId]
  }

  isLayerGenerationCurrent(layerId, generation) {
    return this.layerLoadGeneration[layerId] === generation
  }

  async toggleLayer(event) {
    event.preventDefault()

    const checkbox = event.currentTarget
    const layerId = event.params.layer
    const visible = checkbox.checked

    if (!this.mapReady || !this.map) {
      checkbox.checked = false
      return
    }

    if (visible) {
      await this.showLayer(layerId, { checkbox, fitBounds: true })
    } else {
      this.hideLayerWithCheckbox(layerId, checkbox)
    }

    const systemId = this.metroSystemForRoute(layerId)
    if (systemId) this.syncMetroSystemCheckbox(systemId)

    this.syncAllMetroCheckbox()
    this.updateOutOfStationTransfers()
  }

  async showLayer(layerId, { checkbox = null, fitBounds = true } = {}) {
    const control = checkbox || this.checkboxForLayer(layerId)
    if (!this.mapReady || !this.map) return

    const group = this.layerGroups[layerId]
    if (this.layerVisible[layerId] && group?.getLayers().length > 0) {
      if (control) control.checked = true
      if (!this.map.hasLayer(group)) group.addTo(this.map)
      if (fitBounds) this.fitLayerBounds(layerId)
      this.updateOutOfStationTransfers()
      return
    }

    const generation = this.bumpLayerGeneration(layerId)
    this.layerVisible[layerId] = true
    if (control) {
      control.checked = true
      control.disabled = true
    }

    try {
      await this.loadLayer(layerId, generation)

      if (!this.isLayerGenerationCurrent(layerId, generation) || !this.layerVisible[layerId]) {
        return
      }

      const loadedGroup = this.layerGroups[layerId]
      if (!loadedGroup || loadedGroup.getLayers().length === 0) {
        this.hideLayer(layerId)
        if (control) this.resetLayerCheckbox(control, layerId)
        return
      }

      loadedGroup.addTo(this.map)
      if (fitBounds) this.fitLayerBounds(layerId)
      this.updateOutOfStationTransfers()
    } catch (error) {
      console.error("Failed to load layer", layerId, error)
      this.hideLayer(layerId)
      if (control) this.resetLayerCheckbox(control, layerId)
    } finally {
      if (control && this.mapReady) control.disabled = false
    }
  }

  hideLayerWithCheckbox(layerId, checkbox = null) {
    const control = checkbox || this.checkboxForLayer(layerId)
    this.bumpLayerGeneration(layerId)
    this.hideLayer(layerId)
    if (control) {
      control.checked = false
      control.disabled = false
    }
  }

  resetLayerCheckbox(checkbox, layerId) {
    this.layerVisible[layerId] = false
    checkbox.checked = false
  }

  hideLayer(layerId) {
    this.layerVisible[layerId] = false

    const group = this.layerGroups[layerId]
    if (!group) return

    if (this.map.hasLayer(group)) {
      this.map.removeLayer(group)
    }

    group.clearLayers()

    this.clearStationCoordinatesForRoutes(this.routesToLoad(layerId))

    this.routesToLoad(layerId).forEach((route) => {
      if (route?.id) delete this.routeTracksByRouteId[route.id]
    })

    this.updateOutOfStationTransfers()
  }

  async loadLayer(layerId, generation) {
    const group = this.layerGroups[layerId]
    if (!group) return

    const metroRoutes = this.routesToLoad(layerId)
    const routes = metroRoutes.length > 0 ? metroRoutes : (this.routesManifest[layerId] || [])
    if (routes.length === 0) return

    const results = []

    for (const route of routes) {
      try {
        await this.addRouteToGroup(route, layerId, generation)
        results.push({ status: "fulfilled" })
      } catch (reason) {
        results.push({ status: "rejected", reason })
      }
    }

    if (!this.isLayerGenerationCurrent(layerId, generation)) return

    const failures = results.filter((result) => result.status === "rejected")
    if (failures.length > 0) {
      console.warn(`Layer ${layerId}: ${failures.length}/${results.length} routes failed to load`, failures)
    }

    if (group.getLayers().length === 0 && failures.length > 0) {
      throw failures[0].reason
    }
  }

  async addRouteToGroup(route, layerId, generation) {
    const L = window.L
    const data = await this.fetchGeoJSON(route.file || route.url)

    if (!this.isLayerGenerationCurrent(layerId, generation) || !this.layerVisible[layerId]) return

    const group = this.layerGroups[layerId]
    if (!group) return

    const color = this.routeDisplayColor(route) || LAYER_COLORS[layerId] || "#666666"
    const routeRef = route.ref
    if (this.routeSkipsTerminalRoles(route)) this.clearTerminalRolesFromGeoJSON(data)

    const displayData = this.displayGeoJSON(data, route)
    const renderData = this.cloneGeoJSONForRender(this.geoJSONForMapRender(displayData, route))
    this.enrichTerminalStationRoles(renderData, route)

    this.cacheRouteTracks(route.id, displayData)
    this.indexStationCoordinates(route.id, renderData)

    const geoLayer = L.geoJSON(renderData, {
      style: (feature) => this.styleForFeature(feature, color, route),
      pointToLayer: (feature, latlng) => {
        if (this.isInStationTransferRef(feature.properties?.ref)) {
          return this.hiddenStationMarker(latlng)
        }

        return this.stationMarker(feature, latlng, color, routeRef, route.id)
      },
      onEachFeature: (feature, layer) => {
        if (route.id === "airport_mrt" || route.id === "airport_mrt_express") {
          const lineStyle = this.styleForFeature(feature, color, route)
          if (lineStyle.color && typeof layer.setStyle === "function") layer.setStyle(lineStyle)
        }

        this.bindFeaturePopup(feature, layer, route.id)
      }
    })

    if (!this.isLayerGenerationCurrent(layerId, generation) || !this.layerVisible[layerId]) return

    group.addLayer(geoLayer)

    if (layerId === "airport_mrt") this.bringAirportMrtCommuterLinesToFront(group)
  }

  enrichTerminalStationRoles(data, route) {
    const passengerStations = (data.features || []).filter((feature) => {
      return feature.properties?.feature_type === "station" &&
        feature.properties?.passenger_service !== false
    })

    if (passengerStations.length === 0) return

    const assignRole = (feature, role) => {
      feature.properties = { ...feature.properties, station_role: role }
    }

    if (route?.id === "danhai_lrt") {
      this.assignDanhaiTerminalRoles(passengerStations, assignRole)
      return
    }

    if (this.routeSkipsTerminalRoles(route)) {
      this.clearTerminalStationRoles(passengerStations)
      return
    }

    const ordered = this.sortPassengerStationsByRef(passengerStations)

    assignRole(ordered[0], "origin")
    if (ordered.length > 1) {
      assignRole(ordered[ordered.length - 1], "destination")
    }
  }

  routeSkipsTerminalRoles(route) {
    if (LOOP_LINE_ROUTE_IDS.has(route?.id)) return true

    const source = route?.file || route?.url || ""
    return LOOP_LINE_ROUTE_IDS.has(source.split("/").pop()?.replace(".geojson", ""))
  }

  clearTerminalRolesFromGeoJSON(data) {
    ;(data?.features || []).forEach((feature) => this.clearTerminalStationRoles([ feature ]))
  }

  clearTerminalStationRoles(stations) {
    stations.forEach((feature) => {
      if (feature.properties?.station_role) delete feature.properties.station_role
    })
  }

  cloneGeoJSONForRender(data) {
    return {
      ...data,
      features: (data.features || []).map((feature) => ({
        ...feature,
        properties: feature.properties ? { ...feature.properties } : feature.properties
      }))
    }
  }

  sortPassengerStationsByRef(stations) {
    return stations.slice().sort((left, right) => {
      return this.compareStationRefs(left.properties?.ref, right.properties?.ref)
    })
  }

  compareStationRefs(leftRef, rightRef) {
    const left = this.stationRefSortKey(leftRef)
    const right = this.stationRefSortKey(rightRef)

    for (let index = 0; index < Math.max(left.length, right.length); index += 1) {
      const leftPart = left[index]
      const rightPart = right[index]

      if (leftPart === rightPart) continue
      if (leftPart === undefined) return -1
      if (rightPart === undefined) return 1

      if (typeof leftPart === "number" && typeof rightPart === "number") {
        return leftPart - rightPart
      }

      return String(leftPart).localeCompare(String(rightPart))
    }

    return 0
  }

  stationRefSortKey(ref) {
    const value = (ref || "").split(";")[0]
    const prefix = value.match(/^[A-Z]+/)?.[0] || ""
    const numeric = value.match(/\d+/)?.[0] || "0"
    const suffix = value.slice(prefix.length + numeric.length)
    const suffixRank = /^\d+[a-z]$/i.test(value) ? 0 : suffix ? 2 : 1

    return [ prefix, parseInt(numeric, 10), suffixRank, suffix ]
  }

  assignDanhaiTerminalRoles(passengerStations, assignRole) {
    passengerStations.forEach((feature) => {
      if (feature.properties?.station_role) delete feature.properties.station_role
    })

    this.assignDanhaiTerminalRole(passengerStations, assignRole, DANHAI_SHARED_ORIGIN_REF, "origin", [ "lushan", "lanhai" ])
    this.assignDanhaiTerminalRole(passengerStations, assignRole, DANHAI_LUSHAN_DESTINATION_REF, "destination", [ "lushan" ])
    this.assignDanhaiTerminalRole(passengerStations, assignRole, DANHAI_LANHAI_DESTINATION_REF, "destination", [ "lanhai" ])
  }

  assignDanhaiTerminalRole(passengerStations, assignRole, ref, role, segments) {
    passengerStations.forEach((feature) => {
      if (feature.properties?.ref !== ref) return
      if (!segments.some((segment) => this.danhaiFeatureOnSegment(feature, segment))) return

      assignRole(feature, role)
    })
  }

  danhaiFeatureOnSegment(feature, segment) {
    if (feature.properties?.segment === segment) return true

    return feature.properties?.danhai_segments?.includes(segment) || false
  }

  sortDanhaiSegmentStations(stations, segment) {
    const sortKey = (ref) => {
      if (DANHAI_SHARED_STATION_REFS.has(ref)) return parseInt(ref.slice(1), 10)

      if (segment === "lanhai") {
        const lanhaiIndex = DANHAI_LANHAI_STATION_ORDER.indexOf(ref)
        if (lanhaiIndex >= 0) return 10 + lanhaiIndex
      }

      const match = ref.match(/V(\d+)/i)
      return match ? parseInt(match[1], 10) : 99
    }

    return stations.slice().sort((left, right) => {
      return sortKey(left.properties?.ref) - sortKey(right.properties?.ref)
    })
  }

  isTerminalStation(feature) {
    const role = feature?.properties?.station_role
    return role === "origin" || role === "destination"
  }

  terminalStationLabel(feature) {
    const role = feature?.properties?.station_role
    if (role === "origin") return "起點"
    if (role === "destination") return "終點"
    return null
  }

  geoJSONForMapRender(data, route) {
    let features = data.features || []

    if (route?.id === "danhai_lrt") {
      features = this.deduplicateDanhaiStationFeatures(features)
    }

    if (route?.id === "airport_mrt_express") {
      features = features.filter((feature) => feature.properties?.feature_type !== "station")
    }

    return { ...data, features }
  }

  deduplicateDanhaiStationFeatures(features) {
    const stationsByRef = new Map()
    const output = []

    features.forEach((feature) => {
      if (feature.properties?.feature_type !== "station") {
        output.push(feature)
        return
      }

      const ref = feature.properties?.ref
      if (!ref || !DANHAI_SHARED_STATION_REFS.has(ref)) {
        output.push(feature)
        return
      }

      const existing = stationsByRef.get(ref)
      if (!existing) {
        const segments = feature.properties?.segment ? [ feature.properties.segment ] : []
        stationsByRef.set(ref, {
          ...feature,
          properties: {
            ...feature.properties,
            danhai_segments: segments
          }
        })
        return
      }

      const segments = existing.properties.danhai_segments || []
      const segment = feature.properties?.segment
      if (segment && !segments.includes(segment)) segments.push(segment)
      existing.properties.danhai_segments = segments

      const [ lng, lat ] = feature.geometry?.coordinates || []
      const [ existingLng, existingLat ] = existing.geometry?.coordinates || []
      if (lng == null || lat == null || existingLng == null || existingLat == null) return

      existing.geometry = {
        type: "Point",
        coordinates: [ (existingLng + lng) / 2, (existingLat + lat) / 2 ]
      }
    })

    return output.concat(Array.from(stationsByRef.values()))
  }

  danhaiLineLabel(feature) {
    const segments = feature.properties?.danhai_segments
    if (!segments || segments.length === 0) return feature.properties?.line

    const labels = segments.map((segment) => (segment === "lushan" ? "綠山線" : "藍海線"))

    return `淡海輕軌（${labels.join("／")}）`
  }

  bringAirportMrtCommuterLinesToFront(group) {
    group.eachLayer((container) => {
      if (typeof container.eachLayer !== "function") return

      container.eachLayer((layer) => {
        const path = layer._path || layer.getElement?.()
        if (path?.classList?.contains("airport-mrt-commuter-line") && typeof layer.bringToFront === "function") {
          layer.bringToFront()
        }
      })
    })
  }

  isAirportMrtExpressStop(ref) {
    return ref && AIRPORT_MRT_EXPRESS_STOP_REFS.has(ref)
  }

  isAirportMrtExpressTransferStation(routeId, ref) {
    if (!this.isAirportMrtExpressStop(ref)) return false

    return routeId === "airport_mrt" || routeId === "airport_mrt_express"
  }

  routeDisplayColor(route) {
    if (!route) return null

    if (route.id === "airport_mrt") return AIRPORT_MRT_COMMUTER_COLOR
    if (route.id === "airport_mrt_express") return EXPRESS_LINE_COLOR
    if (route.id === "danhai_lrt") return DANHAI_LRT_COLOR

    return route.color || null
  }

  styleForFeature(feature, color, route = null) {
    if (feature.geometry?.type !== "LineString" && feature.geometry?.type !== "MultiLineString") {
      return {}
    }

    const isExpress = feature.properties?.feature_type === "express_route" ||
      feature.properties?.service_type === "express" ||
      route?.id === "airport_mrt_express"

    if (isExpress) {
      return {
        pane: this.expressRoutePane,
        className: "airport-mrt-express-line",
        color: EXPRESS_LINE_COLOR,
        weight: 6,
        opacity: 1,
        lineCap: "round",
        lineJoin: "round"
      }
    }

    if (route?.id === "airport_mrt") {
      return {
        pane: this.commuterRoutePane,
        className: "airport-mrt-commuter-line",
        color: AIRPORT_MRT_COMMUTER_COLOR,
        weight: 6,
        opacity: 0.95,
        lineCap: "round",
        lineJoin: "round"
      }
    }

    if (route?.id === "danhai_lrt") {
      return {
        color: DANHAI_LRT_COLOR,
        weight: 6,
        opacity: 0.95,
        lineCap: "round",
        lineJoin: "round"
      }
    }

    return {
      color: feature.properties?.color || this.routeDisplayColor(route) || color,
      weight: 5,
      opacity: 0.9,
      lineCap: "round",
      lineJoin: "round"
    }
  }

  stationColorForRoute(routeId, feature, stationRef, fallbackColor) {
    if (routeId === "airport_mrt") return AIRPORT_MRT_COMMUTER_COLOR
    if (routeId === "airport_mrt_express") {
      return feature.properties?.express_service ? EXPRESS_LINE_COLOR : AIRPORT_MRT_COMMUTER_COLOR
    }
    if (routeId === "danhai_lrt") return DANHAI_LRT_COLOR

    return feature.properties?.color || this.colorForStationRef(stationRef) || fallbackColor
  }

  visibleRouteLayerIds() {
    return this.routeLayerIds().filter((layerId) => this.layerVisible[layerId])
  }

  loadedLinePrefixes() {
    return this.visibleRouteLayerIds()
      .map((layerId) => this.findRoute(layerId)?.ref)
      .filter(Boolean)
  }

  cacheRouteTracks(routeId, data) {
    this.routeTracksByRouteId[routeId] = this.extractRouteTracks(data)
  }

  extractRouteTracks(data) {
    const lines = []

    ;(data.features || []).forEach((feature) => {
      const featureType = feature.properties?.feature_type
      if (featureType !== "route" && featureType !== "express_route") return

      const geometry = feature.geometry
      if (geometry?.type === "LineString") {
        lines.push(geometry.coordinates)
      } else if (geometry?.type === "MultiLineString") {
        geometry.coordinates.forEach((coordinates) => lines.push(coordinates))
      }
    })

    return lines
  }

  routeUsesParallelTracks(route) {
    if (!PARALLEL_TRACK_ROUTE_IDS.has(route?.id)) return false

    // Danhai LRT: zoomed out should read as a single line.
    if (route?.id === "danhai_lrt") {
      const zoom = this.map?.getZoom() ?? 12
      return zoom >= 13
    }

    return true
  }

  scheduleParallelTracksRefresh() {
    if (this.parallelTracksRefreshTimer) clearTimeout(this.parallelTracksRefreshTimer)

    this.parallelTracksRefreshTimer = setTimeout(() => {
      this.parallelTracksRefreshTimer = null
      this.refreshVisibleParallelLayers()
    }, 80)
  }

  async refreshVisibleParallelLayers() {
    if (!this.mapReady || !this.map) return

    const layerIds = this.visibleRouteLayerIds().filter((layerId) => {
      return this.routesToLoad(layerId).some((route) => this.routeUsesParallelTracks(route))
    })

    for (const layerId of layerIds) {
      const generation = this.bumpLayerGeneration(layerId)
      const group = this.layerGroups[layerId]
      if (!group) continue

      group.clearLayers()

      try {
        await this.loadLayer(layerId, generation)
      } catch (error) {
        console.warn("Failed to refresh parallel tracks for", layerId, error)
        continue
      }

      if (!this.isLayerGenerationCurrent(layerId, generation) || !this.layerVisible[layerId]) continue

      if (group.getLayers().length > 0) {
        if (!this.map.hasLayer(group)) group.addTo(this.map)
        if (layerId === "airport_mrt") this.bringAirportMrtCommuterLinesToFront(group)
      }

    }

    if (layerIds.length > 0) {
      this.reindexVisibleStationCoordinates()
      this.updateOutOfStationTransfers()
      this.updateMetroDepots()
    }
  }

  metersPerPixelAt(lat) {
    const zoom = this.map?.getZoom() ?? 10
    const safeLat = Math.max(-85, Math.min(85, lat))

    return 40075016.686 * Math.cos(safeLat * Math.PI / 180) / (256 * Math.pow(2, zoom))
  }

  centerLatOfGeoJSON(data) {
    for (const feature of data.features || []) {
      const coordinates = feature.geometry?.coordinates
      if (feature.geometry?.type === "LineString" && coordinates?.length >= 2) {
        const mid = coordinates[Math.floor(coordinates.length / 2)]
        return mid[1]
      }

      if (feature.geometry?.type === "Point" && coordinates?.length >= 2) {
        return coordinates[1]
      }
    }

    return 25.05
  }

  parallelHalfOffsetMeters(data) {
    const lat = this.centerLatOfGeoJSON(data)

    return this.metersPerPixelAt(lat) * PARALLEL_TRACK_HALF_OFFSET_PX
  }

  referenceRouteLine(route, data) {
    if (route.id === "airport_mrt_express") {
      const mainRoute = this.findRoute("airport_mrt")
      const mainFile = mainRoute?.file || mainRoute?.url
      const mainData = mainFile ? this.geoJSONDataByUrl[mainFile] : null

      if (mainData) {
        const mainLine = this.routeLineCoordinates(mainData)
        if (mainLine.length >= 2) return mainLine
      }
    }

    return this.routeLineCoordinates(data)
  }

  danhaiRouteLineForSegment(data, segment) {
    for (const feature of data.features || []) {
      if (feature.properties?.feature_type !== "route") continue
      if (feature.properties?.segment !== segment) continue

      const coordinates = feature.geometry?.coordinates
      if (feature.geometry?.type === "LineString" && coordinates?.length >= 2) return coordinates
    }

    return []
  }

  parallelOffsetMetersForFeature(route, feature, halfOffset) {
    const featureType = feature.properties?.feature_type
    if (featureType !== "route" && featureType !== "station") return null

    if (route.id === "airport_mrt") return -halfOffset
    if (route.id === "airport_mrt_express") return halfOffset

    if (route.id === "danhai_lrt") {
      const segment = feature.properties?.segment
      if (segment === "lushan") return -halfOffset
      if (segment === "lanhai") return halfOffset
    }

    return null
  }

  bearingLineForFeature(route, feature, data, referenceLine) {
    if (route.id === "airport_mrt" || route.id === "airport_mrt_express") {
      return referenceLine.length >= 2 ? referenceLine : this.coordinatesFromFeature(feature)
    }

    if (feature.properties?.segment) {
      const segmentLine = this.danhaiRouteLineForSegment(data, feature.properties.segment)
      if (segmentLine.length >= 2) return segmentLine
    }

    return this.coordinatesFromFeature(feature) || referenceLine
  }

  coordinatesFromFeature(feature) {
    const coordinates = feature.geometry?.coordinates
    if (feature.geometry?.type === "LineString" && coordinates?.length >= 2) return coordinates

    return []
  }

  displayGeoJSON(data, route) {
    if (!route || !this.routeUsesParallelTracks(route)) return data

    const referenceLine = this.referenceRouteLine(route, data)
    const halfOffset = this.parallelHalfOffsetMeters(data)

    return {
      ...data,
      features: (data.features || []).map((feature) => {
        const offset = this.parallelOffsetMetersForFeature(route, feature, halfOffset)
        if (!offset) return feature

        const bearingLine = this.bearingLineForFeature(route, feature, data, referenceLine)

        return this.offsetFeatureCoordinates(feature, offset, bearingLine)
      })
    }
  }

  routeLineCoordinates(data) {
    for (const feature of data.features || []) {
      const featureType = feature.properties?.feature_type
      if (featureType !== "route" && featureType !== "express_route") continue

      const coordinates = feature.geometry?.coordinates
      if (feature.geometry?.type === "LineString" && coordinates?.length >= 2) return coordinates
    }

    return []
  }

  offsetFeatureCoordinates(feature, offsetMeters, routeLine) {
    const geometry = feature.geometry
    if (!geometry) return feature

    if (geometry.type === "LineString") {
      return {
        ...feature,
        geometry: {
          ...geometry,
          coordinates: this.offsetLineStringCoordinates(geometry.coordinates, offsetMeters)
        }
      }
    }

    if (geometry.type === "Point" && routeLine.length >= 2) {
      return {
        ...feature,
        geometry: {
          ...geometry,
          coordinates: this.offsetPointCoordinate(geometry.coordinates, routeLine, offsetMeters)
        }
      }
    }

    return feature
  }

  offsetLineStringCoordinates(coordinates, offsetMeters) {
    if (!coordinates || coordinates.length < 2 || offsetMeters === 0) return coordinates

    return coordinates.map((coordinate, index) => {
      const bearing = this.bearingAlongLine(coordinates, index)
      return this.offsetCoordinate(coordinate, bearing + 90, offsetMeters)
    })
  }

  offsetPointCoordinate(coordinate, lineCoordinates, offsetMeters) {
    const segmentIndex = this.nearestSegmentIndexOnLine(lineCoordinates, coordinate)
    const bearing = this.bearingAlongLine(lineCoordinates, segmentIndex)

    return this.offsetCoordinate(coordinate, bearing + 90, offsetMeters)
  }

  nearestSegmentIndexOnLine(lineCoordinates, point) {
    let bestIndex = 0
    let bestDistance = Infinity

    for (let index = 0; index < lineCoordinates.length - 1; index += 1) {
      const projected = this.projectOnSegmentCoordinates(point, lineCoordinates[index], lineCoordinates[index + 1])
      const distance = this.planarDistanceSquared(projected, point)

      if (distance < bestDistance) {
        bestDistance = distance
        bestIndex = index
      }
    }

    return bestIndex
  }

  projectOnSegmentCoordinates(point, start, end) {
    const dx = end[0] - start[0]
    const dy = end[1] - start[1]

    if (dx === 0 && dy === 0) return start

    const t = Math.max(0, Math.min(1, (
      (point[0] - start[0]) * dx + (point[1] - start[1]) * dy
    ) / (dx * dx + dy * dy)))

    return [ start[0] + t * dx, start[1] + t * dy ]
  }

  planarDistanceSquared(a, b) {
    const dx = a[0] - b[0]
    const dy = a[1] - b[1]

    return (dx * dx) + (dy * dy)
  }

  bearingAlongLine(coordinates, index) {
    const prev = coordinates[Math.max(0, index - 1)]
    const next = coordinates[Math.min(coordinates.length - 1, index + 1)]

    return this.bearingDegrees(prev[1], prev[0], next[1], next[0])
  }

  bearingDegrees(lat1, lng1, lat2, lng2) {
    const lat1Rad = lat1 * Math.PI / 180
    const lat2Rad = lat2 * Math.PI / 180
    const deltaLng = (lng2 - lng1) * Math.PI / 180
    const y = Math.sin(deltaLng) * Math.cos(lat2Rad)
    const x = Math.cos(lat1Rad) * Math.sin(lat2Rad) -
      Math.sin(lat1Rad) * Math.cos(lat2Rad) * Math.cos(deltaLng)

    return (Math.atan2(y, x) * 180 / Math.PI + 360) % 360
  }

  offsetCoordinate([ lng, lat ], bearingDegrees, distanceMeters) {
    const earthRadius = 6378137
    const bearing = bearingDegrees * Math.PI / 180
    const latRad = lat * Math.PI / 180
    const lngRad = lng * Math.PI / 180
    const angularDistance = distanceMeters / earthRadius
    const lat2 = Math.asin(
      Math.sin(latRad) * Math.cos(angularDistance) +
      Math.cos(latRad) * Math.sin(angularDistance) * Math.cos(bearing)
    )
    const lng2 = lngRad + Math.atan2(
      Math.sin(bearing) * Math.sin(angularDistance) * Math.cos(latRad),
      Math.cos(angularDistance) - Math.sin(latRad) * Math.sin(lat2)
    )

    return [ lng2 * 180 / Math.PI, lat2 * 180 / Math.PI ]
  }

  snapToRouteTracks(latlng, routeId) {
    const lines = this.routeTracksByRouteId[routeId] || []
    if (lines.length === 0) return latlng

    const snapped = this.nearestPointOnLines(latlng, lines)
    if (latlng.distanceTo(snapped) > MAX_SNAP_DISTANCE_METERS) return latlng

    return snapped
  }

  tracksForLinePrefix(linePrefix) {
    const lines = []

    this.visibleRouteLayerIds().forEach((layerId) => {
      this.routesToLoad(layerId).forEach((route) => {
        if (!route || route.ref !== linePrefix) return

        const routeLines = this.routeTracksByRouteId[route.id] || []
        lines.push(...routeLines)
      })
    })

    return lines
  }

  snapToTracks(latlng, linePrefix) {
    const lines = this.tracksForLinePrefix(linePrefix)
    if (lines.length === 0) return latlng

    const snapped = this.nearestPointOnLines(latlng, lines)
    if (latlng.distanceTo(snapped) > MAX_SNAP_DISTANCE_METERS) return latlng

    return snapped
  }

  nearestPointOnLines(latlng, lines) {
    let bestLatLng = latlng
    let bestDistance = Infinity

    lines.forEach((coordinates) => {
      for (let index = 0; index < coordinates.length - 1; index += 1) {
        const start = window.L.latLng(coordinates[index][1], coordinates[index][0])
        const end = window.L.latLng(coordinates[index + 1][1], coordinates[index + 1][0])
        const projected = this.projectPointOnSegment(latlng, start, end)
        const distance = latlng.distanceTo(projected)

        if (distance < bestDistance) {
          bestDistance = distance
          bestLatLng = projected
        }
      }
    })

    return bestLatLng
  }

  projectPointOnSegment(point, start, end) {
    const dx = end.lng - start.lng
    const dy = end.lat - start.lat

    if (dx === 0 && dy === 0) return start

    const t = Math.max(0, Math.min(1, (
      (point.lng - start.lng) * dx + (point.lat - start.lat) * dy
    ) / (dx * dx + dy * dy)))

    return window.L.latLng(start.lat + t * dy, start.lng + t * dx)
  }

  transferConnectionLayers(latlngs, kind) {
    const L = window.L
    const path = this.outOfStationTransferLatLngs(latlngs)
    if (kind === "passage") {
      return [
        L.polyline(path, {
          pane: this.outOfStationTransferPane,
          color: TRANSFER_LINE_COLOR,
          weight: 5,
          opacity: 0.95,
          lineCap: "round",
          lineJoin: "round",
          className: "out-of-station-transfer-line out-of-station-transfer-line--passage",
          dashArray: "12 8"
        })
      ]
    }

    const coordinates = path.map((latlng) => [ latlng.lng, latlng.lat ])
    const offsets = [ FARE_DISCOUNT_TRACK_OFFSET_METERS, -FARE_DISCOUNT_TRACK_OFFSET_METERS ]
    const layers = []

    offsets.forEach((offset) => {
      const offsetCoords = this.offsetLineStringCoordinates(coordinates, offset)
      const offsetPath = offsetCoords.map(([ lng, lat ]) => L.latLng(lat, lng))

      // Light casing improves contrast on both light and dark basemaps.
      layers.push(L.polyline(offsetPath, {
        pane: this.outOfStationTransferPane,
        color: "#ffffff",
        weight: 9,
        opacity: 0.88,
        lineCap: "round",
        lineJoin: "round",
        className: "out-of-station-transfer-line out-of-station-transfer-line--fare-discount-casing",
        dashArray: "14 7"
      }))

      layers.push(L.polyline(offsetPath, {
        pane: this.outOfStationTransferPane,
        color: TRANSFER_LINE_COLOR_FARE_DISCOUNT,
        weight: 6,
        opacity: 1,
        lineCap: "round",
        lineJoin: "round",
        className: "out-of-station-transfer-line out-of-station-transfer-line--fare-discount",
        dashArray: "14 7"
      }))
    })

    return layers
  }

  transferPopupHtml(label, kind) {
    const note = this.transferNoteForKind(kind)
    return `<strong>${label}</strong><br><span style="opacity:0.8">${note}</span>`
  }

  outOfStationTransferLatLngs(latlngs) {
    if (latlngs.length !== 2) return latlngs

    const [start, end] = latlngs
    const midLat = (start.lat + end.lat) / 2
    const midLng = (start.lng + end.lng) / 2
    const deltaLat = end.lat - start.lat
    const deltaLng = end.lng - start.lng
    const length = Math.hypot(deltaLat, deltaLng) || 1
    const bulgeScale = 0.00045

    const bulge = window.L.latLng(
      midLat + (-deltaLng / length) * bulgeScale,
      midLng + (deltaLat / length) * bulgeScale
    )

    return [ start, bulge, end ]
  }

  isOutOfStationEndpoint(routeId, ref) {
    if (!routeId || !ref) return false

    return this.transferStationRefs(ref).some((stationRef) => {
      return this.outOfStationEndpointKeys?.has(this.stationKey(routeId, stationRef))
    })
  }

  stationMarker(feature, latlng, color, routeRef, routeId) {
    const L = window.L

    if (feature.properties?.feature_type !== "station" && feature.properties?.feature_type !== "angle_station") {
      return L.marker(latlng)
    }

    if (feature.properties?.feature_type === "angle_station" || feature.properties?.passenger_service === false) {
      const lineColor = feature.properties?.color || this.routeDisplayColor(this.findRoute(routeId)) || color
      const linePrefix = this.linePrefixForStationRef(feature.properties?.ref) || routeRef
      const position = this.snapToTracks(latlng, linePrefix)

      return this.angleStationMarkerAt(position, lineColor)
    }

    const stationRef = feature.properties?.ref

    if (this.isAirportMrtExpressTransferStation(routeId, stationRef)) {
      const position = this.snapToRouteTracks(latlng, "airport_mrt")

      return this.transferStationMarkerAt(position, [ AIRPORT_MRT_COMMUTER_COLOR, EXPRESS_LINE_COLOR ])
    }

    if (feature.properties?.express_service) {
      return this.expressStopMarkerAt(latlng, EXPRESS_LINE_COLOR)
    }

    const stationRefs = this.transferStationRefs(stationRef)
    const primaryStationRef = stationRefs[0]
    const linePrefix = this.linePrefixForStationRef(primaryStationRef) || routeRef
    const lineColor = this.stationColorForRoute(routeId, feature, primaryStationRef, color)
    const outOfStation = this.isOutOfStationEndpoint(routeId, stationRef)
    const usesRouteTrackSnap = routeId === "airport_mrt" || routeId === "airport_mrt_express" || routeId === "circular_lrt"
    const position = outOfStation
      ? latlng
      : usesRouteTrackSnap
        ? this.snapToRouteTracks(latlng, routeId)
        : this.snapToTracks(latlng, linePrefix)

    if (outOfStation) return this.outOfStationMarkerAt(position, lineColor)

    if (this.isTerminalStation(feature)) return this.terminalMarkerAt(position, lineColor)

    return this.circleMarkerAt(position, lineColor)
  }

  terminalMarkerAt(latlng, color) {
    const L = window.L
    const safeColor = color || "#666666"
    const size = Math.max(this.stationMarkerRadius() + 6, 14)
    const html = `<div class="terminal-station-marker" aria-hidden="true" style="--terminal-line-color:${safeColor}"></div>`

    return L.marker(latlng, {
      icon: L.divIcon({
        className: "terminal-station-icon",
        html,
        iconSize: [ size, size ],
        iconAnchor: [ size / 2, size / 2 ]
      }),
      pane: this.stationMarkerPane,
      zIndexOffset: 520
    })
  }

  transferStationMarkerAt(latlng, colors) {
    const L = window.L
    const [leftColor, rightColor] = colors
    const safeLeft = leftColor || "#666666"
    const safeRight = rightColor || safeLeft

    const html = `
      <div class="transfer-station-marker" aria-hidden="true">
        <div class="transfer-station-marker__half" style="background-color:${safeLeft}"></div>
        <div class="transfer-station-marker__half" style="background-color:${safeRight}"></div>
      </div>
    `

    return L.marker(latlng, {
      icon: L.divIcon({
        className: "transfer-station-icon",
        html,
        iconSize: [ 20, 14 ],
        iconAnchor: [ 10, 7 ]
      }),
      pane: this.stationMarkerPane,
      zIndexOffset: 500
    })
  }

  transferStationRefs(ref) {
    if (!ref || !ref.includes(";")) return ref ? [ ref ] : []

    return ref.split(";").map((part) => part.trim()).filter(Boolean)
  }

  linePrefixForStationRef(stationRef) {
    return stationRef?.match(/^[A-Z]+/)?.[0] || null
  }

  colorForStationRef(stationRef) {
    const prefix = this.linePrefixForStationRef(stationRef)
    if (!prefix) return null

    const routes = this.routesByLineRef[prefix] || []
    if (routes.length === 0) return null

    if (prefix === "A") {
      const airportRoute = routes.find((route) => route.id === "airport_mrt")
      if (airportRoute) return AIRPORT_MRT_COMMUTER_COLOR
    }

    if (routes.length === 1) return this.routeDisplayColor(routes[0]) || routes[0].color

    const mainRoute = routes.find((route) => !route.branch_of)
    const branchRoute = routes.find((route) => route.branch_of)

    if (this.isBranchStationRef(stationRef, prefix)) {
      return this.routeDisplayColor(branchRoute) || branchRoute?.color || this.routeDisplayColor(mainRoute) || mainRoute?.color
    }

    return this.routeDisplayColor(mainRoute) || mainRoute?.color || routes[0].color
  }

  isBranchStationRef(stationRef, linePrefix) {
    if (!stationRef || !linePrefix) return false
    if (linePrefix === "A") return false

    return /^[A-Z]+\d+A$/.test(stationRef)
  }

  expressStopMarkerAt(latlng, color) {
    const L = window.L
    const safeColor = color || EXPRESS_LINE_COLOR
    const html = [
      '<div class="express-stop-marker" aria-hidden="true" style="background-color:',
      safeColor,
      '"></div>'
    ].join("")

    return L.marker(latlng, {
      icon: L.divIcon({
        className: "express-stop-station-icon",
        html,
        iconSize: [ 22, 22 ],
        iconAnchor: [ 11, 11 ]
      }),
      pane: this.stationMarkerPane,
      zIndexOffset: 700
    })
  }

  angleStationMarkerAt(latlng, color) {
    const L = window.L
    const safeColor = color || "#00AFE2"
    const html = `<div class="angle-station-marker" aria-hidden="true" style="border-color:${safeColor}"></div>`

    return L.marker(latlng, {
      icon: L.divIcon({
        className: "angle-station-icon",
        html,
        iconSize: [ 18, 18 ],
        iconAnchor: [ 9, 9 ]
      }),
      pane: this.stationMarkerPane,
      zIndexOffset: 550
    })
  }

  outOfStationMarkerAt(latlng, _color) {
    const L = window.L

    const html = `<div class="out-of-station-marker" aria-hidden="true" style="background-color:${OUT_OF_STATION_MARKER_COLOR}"></div>`

    return L.marker(latlng, {
      icon: L.divIcon({
        className: "out-of-station-station-icon",
        html,
        iconSize: [ 18, 18 ],
        iconAnchor: [ 9, 9 ]
      }),
      pane: this.stationMarkerPane,
      zIndexOffset: 600
    })
  }

  stationMarkerRadius() {
    const zoom = this.map?.getZoom() ?? 12

    if (zoom <= 10) return 4
    if (zoom <= 12) return 5
    if (zoom <= 14) return 7

    return 8
  }

  circleMarkerAt(latlng, color) {
    const L = window.L

    return L.circleMarker(latlng, {
      radius: this.stationMarkerRadius(),
      fillColor: color,
      color: "#ffffff",
      weight: 2,
      opacity: 1,
      fillOpacity: 0.95,
      pane: this.stationMarkerPane
    })
  }

  bindFeaturePopup(feature, layer, routeId) {
    const name = feature.properties?.name
    if (!name) return

    const ref = feature.properties?.ref
    const line = routeId === "danhai_lrt" ? this.danhaiLineLabel(feature) : feature.properties?.line
    const label = ref ? `${ref} ${name}` : name
    const subtitle = line ? `<br><span style="opacity:0.8">${line}</span>` : ""
    const terminalLabel = this.terminalStationLabel(feature)
    const terminalNote = terminalLabel ? `<br><span style="opacity:0.8">${terminalLabel}</span>` : ""
    const transferKind = ref ? this.transferKindByEndpointKey?.get(this.stationKey(routeId, ref)) : null
    const transferNote = transferKind
      ? `<br><span style="opacity:0.8">${this.transferNoteForKind(transferKind)}</span>`
      : this.isOutOfStationEndpoint(routeId, ref)
        ? `<br><span style="opacity:0.8">站外轉乘</span>`
        : ""
    const expressNote = this.isAirportMrtExpressStop(ref) && (routeId === "airport_mrt" || routeId === "airport_mrt_express")
      ? `<br><span style="opacity:0.8">普通車／直達車交會</span>`
      : feature.properties?.express_service
        ? `<br><span style="opacity:0.8">直達車停靠</span>`
        : ""
    const boardingAreaNote = feature.properties?.boarding_area === "secured"
      ? `<br><span style="opacity:0.8">管制區內搭乘</span>`
      : feature.properties?.boarding_area === "public"
        ? `<br><span style="opacity:0.8">管制區外搭乘</span>`
        : ""
    const directionNote = feature.properties?.note && feature.properties?.passenger_service !== false
      ? `<br><span style="opacity:0.8">${feature.properties.note}</span>`
      : ""
    const noPassengerServiceNote = feature.properties?.feature_type === "angle_station" ||
      feature.properties?.passenger_service === false
      ? `<br><span style="opacity:0.8">不提供載客服務</span>`
      : ""
    const popup = `<strong>${label}</strong>${subtitle}${terminalNote}${boardingAreaNote}${noPassengerServiceNote}${directionNote}${transferNote}${expressNote}`

    layer.bindPopup(popup)
  }

  async fetchGeoJSON(url) {
    if (!this.geoJSONCache[url]) {
      this.geoJSONCache[url] = fetch(url).then(async (response) => {
        if (!response.ok) throw new Error(`Failed to load ${url}`)
        const data = await response.json()
        this.geoJSONDataByUrl[url] = data
        return data
      })
    }

    return this.geoJSONCache[url]
  }

  fitLayerBounds(layerId) {
    const group = this.layerGroups[layerId]
    if (!group || group.getLayers().length === 0 || !this.map) return

    try {
      const bounds = group.getBounds()
      if (bounds.isValid()) {
        this.map.fitBounds(bounds.pad(0.1))
      }
    } catch (error) {
      console.warn("Could not fit bounds for layer", layerId, error)
    }
  }
}
