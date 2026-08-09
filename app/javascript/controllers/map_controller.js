// airport-mrt-colors-v3: commuter #0073B7, express #6A2C91, solid parallel tracks
import { Controller } from "@hotwired/stimulus"
import { VehicleCanvasLayer } from "transit/vehicle_canvas_layer"
import { motionKind, easedProgress, speedKmh } from "transit/motion_profile"
import { buildChainage, longestTrackLine, nearestDistance, pointAtDistance } from "transit/track_chainage"

const LEAFLET_BOUNDS = [ [ 21.85, 118.15 ], [ 26.45, 122.25 ] ]

const BASE_LAYERS = [ "bus", "train", "ferry" ]

const LAYER_COLORS = {
  bus: "#2563eb",
  train: "#dc2626",
  hsr: "#DB5325",
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
const OUT_OF_STATION_MARKER_COLOR = "#737373"
// Class 2–4 connection strength: solid (passage) > dashed (fare discount) > dotted (named walk).
const TRANSFER_LINE_COLOR_PASSAGE = "#404040"
const TRANSFER_LINE_COLOR_FARE_DISCOUNT = "#737373"
const TRANSFER_LINE_COLOR_WALK = "#a3a3af"
const TRANSFER_LINE_WEIGHT_PASSAGE = 5
const TRANSFER_LINE_WEIGHT_FARE_DISCOUNT = 4
const TRANSFER_LINE_WEIGHT_WALK = 3
const PARALLEL_TRACK_HALF_OFFSET_M = 25
const PARALLEL_TRACK_ROUTE_IDS = new Set([
  "airport_mrt",
  "airport_mrt_express",
  "danhai_lrt",
  "taoyuan_airport_skytrain"
])
const PARALLEL_TRACK_MIN_ZOOM = 13
const LAYER_LOAD_CONCURRENCY = 6
const VEHICLE_MIN_ZOOM = 5
const VEHICLE_TAG_ZOOM = 10
const STATION_LABEL_MIN_ZOOM = 14
const STATION_LABEL_PRIORITY_ZOOM = 12
const CARTO_LIGHT_BASEMAP_URL = "https://{s}.basemaps.cartocdn.com/light_nolabels/{z}/{x}/{y}{r}.png"
const CARTO_DARK_BASEMAP_URL = "https://{s}.basemaps.cartocdn.com/dark_nolabels/{z}/{x}/{y}{r}.png"
const ESRI_SAT_BASEMAP_URL = "https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}"
const NLSC_BASEMAP_URL = "https://wmts.nlsc.gov.tw/wmts/EMAP/default/GoogleMapsCompatible/{z}/{y}/{x}"
const CARTO_BASEMAP_ATTRIBUTION = '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> &copy; <a href="https://carto.com/">CARTO</a>'
const ESRI_SAT_BASEMAP_ATTRIBUTION = "Tiles &copy; Esri &mdash; Source: Esri, Maxar, Earthstar Geographics"
const NLSC_BASEMAP_ATTRIBUTION = '&copy; <a href="https://maps.nlsc.gov.tw/" target="_blank" rel="noopener">內政部國土測繪中心</a>'
const BASEMAP_MODE_STORAGE_KEY = "map-basemap-style"
const LEGACY_BASEMAP_MODE_STORAGE_KEY = "map-basemap"
const LEGACY_NLSC_ENABLED_STORAGE_KEY = "map-nlsc-enabled"
const NEARBY_PIN_STORAGE_KEY = "map-nearby-pins"
const RIDE_STAMP_STORAGE_KEY = "map-ride-stamps"
const RELAX_MODE_STORAGE_KEY = "map-relax-mode"
const LIVE_OVERLAY_WINDOW_MS = 15 * 60 * 1000
const NEARBY_RADIUS_M = 1500
const STATION_BOARD_MINUTES = 60
const SCHEDULE_FETCH_CHUNK = 8
const SKYTRAIN_NORTH_STATION_ORDER = [ "ST1N", "ST2N" ]
const SKYTRAIN_SOUTH_STATION_ORDER = [ "ST1S", "ST2S" ]
const TRA_BRANCH_ROUTE_IDS = new Set([
  "neiwan_line",
  "liujia_line",
  "jiji_line",
  "pingxi_line",
  "chengzhui_line",
  "shalun_line",
  "shenao_line",
  "hualien_port_line",
  "taichung_port_line"
])
const TRA_BRANCH_ROUTE_PRIORITY = {
  neiwan_line: 1,
  liujia_line: 2,
  jiji_line: 1,
  pingxi_line: 1,
  chengzhui_line: 1,
  shalun_line: 1,
  shenao_line: 1,
  hualien_port_line: 1
}
// Branch origin stations stay on the branch layer even when the parent line is visible.
const TRA_BRANCH_JUNCTION_REFS = {
  neiwan_line: [ "1210" ],
  liujia_line: [ "1193" ],
  pingxi_line: [ "7330" ],
  chengzhui_line: [ "3350", "2260" ],
  pingtung_line: [ "4400" ],
  shalun_line: [ "4270" ],
  shenao_line: [ "7360" ],
  hualien_port_line: [ "7010" ]
}
// Main-line origin stations stay on their line layer when a connecting line is visible.
const TRA_LINE_ORIGIN_REFS = {
  pingtung_line: [ "4400" ],
  south_link: [ "5130" ],
  beihui_line: [ "7000" ],
  taidong_line: [ "6000" ],
  yilan_line: [ "920" ],
  shenao_line: [ "7360" ],
  neiwan_line: [ "1210" ],
  mountain_line: [ "1250" ],
  sea_line: [ "1250" ],
  chengzhui_line: [ "3350" ],
  western_trunk_south: [ "3360" ]
}
// Main-line stations that meet a branch at the same ref.
const TRA_MAIN_LINE_JUNCTION_REFS = {
  mountain_line: [ "3350" ],
  sea_line: [ "2260" ],
  western_trunk_south: [ "4400" ]
}
// Main-line terminal stations stay on their line layer when a connecting line is visible.
const TRA_LINE_FINISH_REFS = {
  beihui_line: [ "7130" ],
  yilan_line: [ "7120" ],
  mountain_line: [ "3360" ],
  sea_line: [ "3360" ],
  chengzhui_line: [ "2260" ],
  western_trunk_north: [ "1250" ],
  western_trunk_south: [ "4400" ]
}

const TRA_BRAND_COLOR = "#004B87"

const METRO_SYSTEM_IDS = [
  "taipei_metro",
  "new_taipei_metro",
  "taoyuan_metro",
  "taichung_metro",
  "kaohsiung_metro"
]

export default class extends Controller {
  static values = {
    initialRouteId: String,
    autoDefaultLayers: { type: Boolean, default: true }
  }

  static targets = [
    "map",
    "layerCheckbox",
    "layersPanel",
    "layersSidebar",
    "layerSearchInput",
    "layerSearchItem",
    "layerSearchGroup",
    "layerSearchEmpty",
    "layerSearchClear",
    "categoryChip",
    "routeBrowser",
    "routeResults",
    "routeStopsPanel",
    "routeStopsTitle",
    "routeStopsMeta",
    "routeStopsList",
    "routeStopsEmpty",
    "basemapSelect",
    "bootOverlay",
    "bootStatus",
    "bootProgressBar",
    "bootCount",
    "bootList"
  ]

  connect() {
    if (this.map) return

    this.initNonce = (this.initNonce || 0) + 1

    this.onSplitResize = () => this.invalidateMapSize()
    window.addEventListener("map-split:resize", this.onSplitResize)

    this.layerGroups = {}
    this.layerVisible = {}
    this.layerLoadGeneration = {}
    this.geoJSONCache = {}
    this.geoJSONDataByUrl = {}
    this.routesManifest = {}
    this.lineColorsByPrefix = {}
    this.routesByLineRef = {}
    this.routeTracksByRouteId = {}
    this.vehicleTracksByRouteId = {}
    this.outOfStationTransfers = []
    this.outOfStationEndpointKeys = new Set()
    this.transferKindByEndpointKey = new Map()
    this.metroDepots = []
    this.stationCoordinatesByKey = {}
    this.stationNameByKey = {}
    this.selectedRouteId = null
    this.stationCoordsByRouteRef = {}
    this.stationLabelEntries = []
    this.mapReady = false
    this.booting = true
    this.bootTasks = []
    this.themeObserver = null
    this.activeCategory = null
    this.basemapStyle = this.readBasemapStyle()
    this.simulationAt = null
    this.simulationPlaying = false
    this.simulationSpeed = 1
    this.vehicleRefreshTimer = null
    this.vehicleFetchController = null
    this.vehicleRequestSeq = 0
    this.vehicleGroup = null
    this.vehicleMarkersById = {}
    this.vehicleRefreshImmediate = false
    this.followedVehicleKey = null
    this.followedMarker = null
    this.followedSoftId = null
    this.followedTrainNumber = null
    this.followedRouteId = null
    this.followedDirection = null
    this.followedDestination = null
    this.followLastLatLng = null
    this.followCameraLocked = false
    this.followMissed = false
    this.followBarEl = null
    this.followHandoff = null
    this.followHandoffKey = null
    this.followHandoffDecision = null
    this.pendingFollowTripId = null
    this.pendingFollowTrainNumber = null
    this.onFollowMapDrag = null
    this.scheduleSnapshots = {}
    this.scheduleDate = null
    this.scheduleFetchController = null
    this.liveOverlayByKey = {}
    this.routeChainage = {}
    this.vehicleCanvas = null
    this.crossingGroup = null
    this.crossingsVisible = false
    this.crossingFeatures = []
    this.pinMode = false
    this.nearbyPins = []
    this.nearbyPinGroup = null
    this.exploreRelax = false
    this.shareTimer = null
    this.pendingShare = null
    this.applyingShare = false
    this.alertBannerEl = null
    this.exploreToolsEl = null
    this.stationBoardEl = null
    this.nearbyPanelEl = null
    this.explorePanelEl = null
    this.dismissedAlertIds = new Set()
    this.setLayerControlsDisabled(true)
    this.syncMobileSidebarAria(false)
    this.element.classList.add("is-booting")
    this.element.setAttribute("aria-busy", "true")
    this.startBootTask("leaflet", this.t("boot.leaflet"))
    this.waitForLeaflet(0)
    this.initializeCategoryFilter()
    this.onSimulationTime = (event) => this.handleSimulationTime(event)
    this.onSimulationSpeed = (event) => this.handleSimulationSpeed(event)
    window.addEventListener("map:simulation-time", this.onSimulationTime)
    window.addEventListener("map:simulation-speed", this.onSimulationSpeed)
  }

  disconnect() {
    this.initNonce = (this.initNonce || 0) + 1
    if (this.onSplitResize) window.removeEventListener("map-split:resize", this.onSplitResize)
    if (this.resizeHandler) window.removeEventListener("resize", this.resizeHandler)
    if (this.parallelTracksRefreshTimer) clearTimeout(this.parallelTracksRefreshTimer)
    if (this.map && this.refreshParallelTracksOnZoom) {
      this.map.off("zoomend", this.refreshParallelTracksOnZoom)
    }
    if (this.map && this.refreshStationLabelsOnView) {
      this.map.off("zoomend", this.refreshStationLabelsOnView)
      this.map.off("moveend", this.refreshStationLabelsOnView)
    }
    if (this.onThemeChanged) window.removeEventListener("theme:changed", this.onThemeChanged)
    if (this.onSimulationTime) window.removeEventListener("map:simulation-time", this.onSimulationTime)
    if (this.onSimulationSpeed) window.removeEventListener("map:simulation-speed", this.onSimulationSpeed)
    if (this.vehicleRefreshTimer) clearTimeout(this.vehicleRefreshTimer)
    if (this.stationLabelRefreshTimer) clearTimeout(this.stationLabelRefreshTimer)
    if (this.vehicleFetchController) this.vehicleFetchController.abort()
    if (this.scheduleFetchController) this.scheduleFetchController.abort()
    this.stopVehicleAnimationLoop()
    this.stopFollowingVehicle({ silent: true })
    this.vehicleCanvas?.remove()
    this.vehicleCanvas = null
    this.alertBannerEl?.remove()
    this.exploreToolsEl?.remove()
    this.stationBoardEl?.remove()
    this.nearbyPanelEl?.remove()
    this.explorePanelEl?.remove()
    if (this.shareTimer) clearTimeout(this.shareTimer)
    if (this.map && this.refreshVehiclesOnView) {
      this.map.off("zoomend", this.refreshVehiclesOnView)
      this.map.off("moveend", this.refreshVehiclesOnView)
    }
    if (this.map && this.onFollowMapDrag) {
      this.map.off("dragstart", this.onFollowMapDrag)
      this.onFollowMapDrag = null
    }
    this.followBarEl?.remove()
    this.followBarEl = null
    this.element?.classList.remove("map-split-layout--layers-open")
    document.body.classList.remove("overflow-hidden")
    this.themeObserver?.disconnect()
    this.themeObserver = null
    this.map?.remove()
    this.map = null
    this.mapReady = false
    this.booting = false
    this.bootTasks = []
    this.tileLayer = null
    this.layerGroups = {}
    this.layerVisible = {}
    this.layerLoadGeneration = {}
    this.geoJSONCache = {}
    this.geoJSONDataByUrl = {}
    this.routesManifest = {}
    this.lineColorsByPrefix = {}
    this.routesByLineRef = {}
    this.routeTracksByRouteId = {}
    this.vehicleTracksByRouteId = {}
    this.outOfStationTransfers = []
    this.outOfStationEndpointKeys = new Set()
    this.transferKindByEndpointKey = new Map()
    this.metroDepots = []
    this.stationCoordinatesByKey = {}
    this.stationNameByKey = {}
    this.stationLabelEntries = []
    this.stationLabelGroup = null
    this.vehicleGroup = null
    this.vehicleMarkersById = {}
    this.simulationAt = null
    this.simulationPlaying = false
    this.simulationSpeed = 1
    this.followedVehicleKey = null
    this.followedMarker = null
    this.followedSoftId = null
    this.followedTrainNumber = null
    this.followedRouteId = null
    this.followedDirection = null
    this.followedDestination = null
    this.followLastLatLng = null
    this.followCameraLocked = false
    this.followMissed = false
  }

  t(key, vars = {}) {
    const parts = String(key).split(".")
    let value = window.MAP_I18N

    for (const part of parts) {
      value = value?.[part]
      if (value == null) return key
    }

    if (typeof value !== "string") return key

    return value.replace(/%\{(\w+)\}/g, (_, name) => {
      const replacement = vars[name]
      return replacement == null ? "" : String(replacement)
    })
  }

  isEnglishLocale() {
    const locale = document.documentElement.dataset.locale || document.documentElement.lang || ""
    return locale === "en" || locale.startsWith("en")
  }

  localizedName(zh, en) {
    if (this.isEnglishLocale() && en) return en
    return zh || en || ""
  }

  routeDisplayName(route) {
    return this.localizedName(route?.name, route?.name_en || route?.nameEn)
  }

  featureDisplayName(feature) {
    const properties = feature?.properties || {}
    const name = this.localizedName(properties.name || "", properties.name_en)
    if (this.isDisplayableStationName(name)) return name

    const ref = String(properties.ref || "").trim()
    return this.isDisplayableStationName(ref) ? ref : ""
  }

  isDisplayableStationName(value) {
    const name = String(value || "").trim()
    return Boolean(name) && !name.includes(";")
  }

  stationDisplayName(station) {
    return this.localizedName(station?.name, station?.nameEn || station?.name_en)
  }

  waitForLeaflet(attempts) {
    if (window.L) {
      this.initMap()
      return
    }

    if (attempts > 60) {
      this.finishBootTask("leaflet", "error")
      this.completeBoot({ failed: true })
      this.element.innerHTML = "<p style=\"padding:1rem;font-family:sans-serif\">Map failed to load. Hard-refresh the page.</p>"
      return
    }

    setTimeout(() => this.waitForLeaflet(attempts + 1), 50)
  }

  async initMap() {
    this.startBootTask("leaflet", this.t("boot.leaflet"))

    const L = window.L
    const mapElement = this.hasMapTarget ? this.mapTarget : this.element

    this.map = L.map(mapElement, {
      zoomControl: true,
      scrollWheelZoom: true,
      dragging: true,
      touchZoom: true,
      zoomAnimation: true,
      markerZoomAnimation: true,
      fadeAnimation: true,
      // Integer zoom levels feel more predictable than continuous fractional zoom.
      zoomSnap: 1,
      zoomDelta: 1,
      wheelPxPerZoomLevel: 80,
      wheelDebounceTime: 40
    })

    this.tileLayer = L.tileLayer(this.primaryBasemapUrl(), {
      ...this.primaryBasemapOptions(),
      updateWhenZooming: true,
      keepBuffer: 2
    }).addTo(this.map)
    this.syncPrimaryBasemapClass()
    this.finishBootTask("leaflet")

    this.watchThemeChanges()
    this.syncBasemapSelect()

    this.onThemeChanged = () => this.applyThemeBasemap()
    window.addEventListener("theme:changed", this.onThemeChanged)

    this.startBootTask("manifest", this.t("boot.manifest"))
    this.startBootTask("transfers", this.t("boot.transfers"))
    this.startBootTask("depots", this.t("boot.depots"))

    await Promise.all([
      this.loadRoutesManifest().then(() => this.finishBootTask("manifest"), () => this.finishBootTask("manifest", "error")),
      this.loadOutOfStationTransfers().then(() => this.finishBootTask("transfers"), () => this.finishBootTask("transfers", "error")),
      this.loadMetroDepots().then(() => this.finishBootTask("depots"), () => this.finishBootTask("depots", "error"))
    ])
    if (!this.map) {
      this.completeBoot({ failed: true })
      return
    }

    const transferPane = this.map.createPane("outOfStationTransfers")
    transferPane.style.zIndex = 640
    this.outOfStationTransferPane = "outOfStationTransfers"

    const expressPane = this.map.createPane("expressRoutes")
    expressPane.style.zIndex = 610
    this.expressRoutePane = "expressRoutes"

    const commuterPane = this.map.createPane("commuterRoutes")
    commuterPane.style.zIndex = 630
    this.commuterRoutePane = "commuterRoutes"

    const stationPane = this.map.createPane("stationMarkers")
    stationPane.style.zIndex = 650
    this.stationMarkerPane = "stationMarkers"

    const stationLabelPane = this.map.createPane("stationLabels")
    stationLabelPane.style.zIndex = 660
    this.stationLabelPane = "stationLabels"

    this.outOfStationTransferGroup = L.featureGroup().addTo(this.map)
    this.crossSystemInStationTransferGroup = L.featureGroup().addTo(this.map)
    this.inStationTransferGroup = L.featureGroup().addTo(this.map)
    this.metroDepotGroup = L.featureGroup().addTo(this.map)
    this.stationLabelGroup = L.layerGroup().addTo(this.map)

    const vehiclePane = this.map.createPane("vehicles")
    vehiclePane.style.zIndex = 700
    this.vehicleGroup = L.layerGroup({ pane: "vehicles" }).addTo(this.map)
    this.vehicleMarkersById = {}
    this.vehicleCanvas = new VehicleCanvasLayer()
    this.vehicleCanvas.addTo(this.map)
    this.vehicleCanvas.onSelect = (entry) => this.handleCanvasVehicleSelect(entry)
    this.crossingGroup = L.layerGroup()
    this.nearbyPinGroup = L.layerGroup().addTo(this.map)
    this.pendingShare = this.readShareParams()
    this.ensureExploreUi()
    this.restoreRelaxMode()
    this.loadStoredPins()
    this.loadAlerts()
    this.loadCrossings()

    this.ensureAllLayerGroups()

    this.map.fitBounds(LEAFLET_BOUNDS)
    this.map.zoomControl.setPosition("topright")
    this.parallelTracksActive = (this.map.getZoom() ?? 12) >= PARALLEL_TRACK_MIN_ZOOM

    this.refreshParallelTracksOnZoom = () => this.scheduleParallelTracksRefresh()
    this.refreshStationLabelsOnView = () => {
      if (this.ignoreMapViewEvents) return
      this.scheduleStationLabelRefresh()
    }
    this.refreshVehiclesOnView = () => {
      if (this.ignoreMapViewEvents) return
      this.redrawVehicleCanvas()
      this.scheduleShareUrlUpdate()
    }
    this.map.on("zoomend", this.refreshParallelTracksOnZoom)
    this.map.on("zoomend", this.refreshStationLabelsOnView)
    this.map.on("moveend", this.refreshStationLabelsOnView)
    this.map.on("zoomend", this.refreshVehiclesOnView)
    this.map.on("moveend", this.refreshVehiclesOnView)

    this.onFollowMapDrag = () => {
      if (this._autoPan || this.ignoreMapViewEvents) return
      if (!this.followedVehicleKey || !this.followCameraLocked) return
      this.followCameraLocked = false
      this.syncFollowBar()
    }
    this.map.on("dragstart", this.onFollowMapDrag)

    this.ensureFollowBar()

    this.resizeHandler = () => this.invalidateMapSize()
    requestAnimationFrame(this.resizeHandler)
    setTimeout(this.resizeHandler, 100)
    setTimeout(this.resizeHandler, 500)
    window.addEventListener("resize", this.resizeHandler)

    this.mapReady = true
    this.syncPanelToggleStates()
    this.syncSimulationFromScrubber()
    try {
      await this.loadInitialRouteFromPage()
      await this.ensureInitialRouteLayers()
      this.syncSimulationFromScrubber()
      await this.applyShareParams()
      await this.bootVehicles()
      this.completeBoot()
      this.scheduleShareUrlUpdate()
    } catch (error) {
      console.error("Map boot failed", error)
      this.completeBoot({ failed: true })
    }
  }

  async loadInitialRouteFromPage() {
    const routeId = this.initialRouteIdValue || new URLSearchParams(window.location.search).get("route")
    if (!routeId) return

    const route = this.findRoute(routeId)
    const label = this.routeDisplayName(route) || routeId
    this.startBootTask(`route:${routeId}`, label)
    this.startBootTask("stops", this.t("boot.stops"))
    try {
      await this.openRouteDetail(routeId)
      this.finishBootTask(`route:${routeId}`)
      this.finishBootTask("stops")
    } catch (error) {
      this.finishBootTask(`route:${routeId}`, "error")
      this.finishBootTask("stops", "error")
      throw error
    }
  }

  // First dashboard visit: show the full route catalog. Trains are not a
  // separate layer — they follow whichever routes are checked.
  // Dedicated route pages already load their route.
  async ensureInitialRouteLayers() {
    if (!this.autoDefaultLayersValue) return
    if (this.initialRouteIdValue) return

    if (this.visibleRouteLayerIds().length > 0) return

    if (this.pendingShare?.routes?.length) {
      const shareRoutes = this.pendingShare.routes.filter((routeId) => Boolean(this.findRoute(routeId)))
      if (shareRoutes.length > 0) {
        await this.setRouteLayersVisible(shareRoutes, true, {
          fitBounds: false,
          afterSync: () => {
            this.syncAllMetroCheckbox()
            this.syncAllTraCheckbox()
            this.syncAllTransitCheckbox()
          }
        })
        return
      }
    }

    await this.setAllTransitLayersVisible(true, { fitBounds: true })
  }

  async bootVehicles() {
    this.startBootTask("vehicles", this.t("boot.vehicles"))
    try {
      await this.fetchAndSyncVehicles()
      this.finishBootTask("vehicles")
    } catch (error) {
      console.warn("vehicles boot fetch failed", error)
      this.finishBootTask("vehicles", "error")
    }
  }

  startBootTask(id, label) {
    if (!this.bootTasks) this.bootTasks = []
    const existing = this.bootTasks.find((task) => task.id === id)
    if (existing) {
      existing.label = label
      existing.status = "loading"
    } else {
      this.bootTasks.push({ id, label, status: "loading" })
    }
    this.renderBootProgress()
  }

  finishBootTask(id, status = "done") {
    const task = this.bootTasks?.find((entry) => entry.id === id)
    if (task) task.status = status === "error" ? "error" : "done"
    this.renderBootProgress()
  }

  renderBootProgress() {
    const tasks = this.bootTasks || []
    const done = tasks.filter((task) => task.status === "done" || task.status === "error").length
    const total = tasks.length
    const percent = total === 0 ? 0 : Math.round((done / total) * 100)
    const current = tasks.find((task) => task.status === "loading")

    if (this.hasBootProgressBarTarget) {
      this.bootProgressBarTarget.style.width = `${percent}%`
    }
    if (this.hasBootCountTarget) {
      this.bootCountTarget.textContent = this.t("boot.count", { done, total })
    }
    if (this.hasBootStatusTarget) {
      this.bootStatusTarget.textContent = current?.label || (total > 0 && done === total ? this.t("boot.ready") : this.t("boot.starting"))
    }
    if (this.hasBootListTarget) {
      this.bootListTarget.replaceChildren(...tasks.map((task) => {
        const item = document.createElement("li")
        item.className = `map-boot-overlay__item map-boot-overlay__item--${task.status}`
        item.textContent = task.label
        return item
      }))
    }
  }

  completeBoot({ failed = false } = {}) {
    this.booting = false
    this.element.classList.remove("is-booting")
    this.element.setAttribute("aria-busy", "false")
    if (this.hasBootStatusTarget) {
      this.bootStatusTarget.textContent = failed ? this.t("boot.failed") : this.t("boot.ready")
    }
    if (this.hasBootOverlayTarget) {
      this.bootOverlayTarget.hidden = true
      this.bootOverlayTarget.setAttribute("aria-busy", "false")
    }
    if (this.mapReady) this.setLayerControlsDisabled(false)
    if (this.mapReady && this.simulationAt) this.scheduleVehicleRefresh()
  }

  async openRouteDetail(routeId) {
    if (!routeId) return

    this.selectedRouteId = routeId
    this.syncRouteSelectionUI()
    this.applyRouteEmphasis()

    const checkbox = this.checkboxForLayer(routeId)
    if (!this.layerVisible[routeId]) {
      await this.showLayer(routeId, { checkbox, fitBounds: true })
    } else if (this.map) {
      this.fitLayerBounds(routeId)
    }

    await this.displayRouteStops(routeId)
    this.refreshStationLabels()
  }

  allLayerIds() {
    return [ ...BASE_LAYERS, ...this.routeLayerIds() ]
  }

  ensureAllLayerGroups() {
    const L = window.L
    if (!L) return

    this.allLayerIds().forEach((layerId) => {
      if (this.layerGroups[layerId]) return

      this.layerGroups[layerId] = L.featureGroup()
      this.layerVisible[layerId] = false
      this.layerLoadGeneration[layerId] = 0
    })
  }

  ensureLayerGroup(layerId) {
    this.ensureAllLayerGroups()
    return this.layerGroups[layerId]
  }

  routeLayerIds() {
    const ids = []

    Object.values(this.routesManifest).forEach((routes) => {
      if (!Array.isArray(routes)) return

      routes.forEach((route) => {
        if (route.id) ids.push(route.id)
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
      const response = await fetch("/geojson/out_of_station_transfers.json", { cache: "force-cache" })
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
    const kind = transfer?.kind
    if (kind === "passage") return "passage"
    if (kind === "walk_transfer") return "walk_transfer"
    if (kind === "fare_discount") return "fare_discount"
    return "fare_discount"
  }

  transferNoteForKind(kind) {
    if (kind === "passage") return this.t("transfer.passage")
    if (kind === "walk_transfer") return this.t("transfer.walk_transfer")
    if (kind === "fare_discount") return this.t("transfer.fare_discount")
    return this.t("transfer.generic")
  }

  async loadMetroDepots() {
    try {
      const response = await fetch("/geojson/metro_depots.json", { cache: "force-cache" })
      if (!response.ok) throw new Error("metro depots missing")

      this.metroDepots = await response.json()
    } catch (error) {
      console.error("Failed to load metro depots", error)
      this.metroDepots = []
    }
  }

  async loadRoutesManifest() {
    try {
      const response = await fetch("/geojson/routes.json", { cache: "no-cache" })
      if (!response.ok) throw new Error("routes manifest missing")
      this.routesManifest = await response.json()
      const { colorsByPrefix, routesByLineRef } = this.buildLineColorMap()
      this.lineColorsByPrefix = colorsByPrefix
      this.routesByLineRef = routesByLineRef
    } catch (error) {
      console.error("Failed to load routes manifest", error)
      this.routesManifest = {}
      this.lineColorsByPrefix = {}
      this.routesByLineRef = {}
    }
  }

  routesToLoad(layerId) {
    return this.routesForLayer(layerId)
  }

  routesForLayer(layerId) {
    const route = this.findRoute(layerId)
    if (!route) return this.routesManifest[layerId] || []

    return [ route ]
  }

  routeSystemRefKey(systemId, ref) {
    return systemId && ref ? `${systemId}:${ref}` : null
  }

  buildLineColorMap() {
    const colorsByPrefix = {}
    const routesByLineRef = {}

    Object.entries(this.routesManifest).forEach(([ systemId, routes ]) => {
      if (!Array.isArray(routes)) return

      routes.forEach((route) => {
        if (!route.ref) return

        const key = this.routeSystemRefKey(systemId, route.ref)
        if (!routesByLineRef[key]) routesByLineRef[key] = []
        routesByLineRef[key].push(route)

        if (!route.branch_of) colorsByPrefix[key] = this.routeDisplayColor(route) || route.color
      })
    })

    return { colorsByPrefix, routesByLineRef }
  }

  routesForSystemRef(systemId, ref) {
    return this.routesByLineRef[this.routeSystemRefKey(systemId, ref)] || []
  }

  routesForLinePrefix(prefix) {
    const visibleIds = new Set(this.visibleRouteLayerIds())
    const visibleRoutes = []
    const allRoutes = []

    Object.entries(this.routesManifest).forEach(([ systemId, routeList ]) => {
      if (!Array.isArray(routeList)) return

      routeList.forEach((route) => {
        if (route.ref !== prefix) return

        allRoutes.push(route)
        if (visibleIds.has(route.id)) visibleRoutes.push(route)
      })
    })

    return visibleRoutes.length > 0 ? visibleRoutes : allRoutes
  }

  async resetView() {
    await this.showAllTransit()
  }

  async showAllMetro() {
    if (!this.mapReady || !this.map) return

    await this.setAllMetroLayersVisible(true, { fitBounds: true })
  }

  async showAllTra() {
    if (!this.mapReady || !this.map) return

    await this.setAllTraLayersVisible(true, { fitBounds: true })
  }

  async showAllTransit() {
    if (!this.mapReady || !this.map) return

    await this.setAllTransitLayersVisible(true, { fitBounds: true })
  }

  resetViewport() {
    if (!this.mapReady || !this.map) return

    this.map.fitBounds(LEAFLET_BOUNDS)
  }

  toggleLayersPanel() {
    if (!this.hasLayersPanelTarget) return

    this.layersPanelTarget.classList.toggle("map-ui-panel--collapsed")
    const collapsed = this.layersPanelTarget.classList.contains("map-ui-panel--collapsed")
    this.element.classList.toggle("map-split-layout--sidebar-collapsed", collapsed)
    this.syncPanelToggleState(this.layersPanelTarget)
    window.dispatchEvent(new CustomEvent("map-split:resize"))
    this.invalidateMapSize()
  }

  openMobileLayers() {
    this.element.classList.add("map-split-layout--layers-open")
    document.body.classList.add("overflow-hidden")
    this.syncMobileSidebarAria(true)
    this.invalidateMapSize()
    if (this.hasLayerSearchInputTarget) this.layerSearchInputTarget.focus()
  }

  closeMobileLayers() {
    this.element.classList.remove("map-split-layout--layers-open")
    document.body.classList.remove("overflow-hidden")
    this.syncMobileSidebarAria(false)
    this.invalidateMapSize()
  }

  syncMobileSidebarAria(open) {
    if (!this.hasLayersSidebarTarget) return
    if (window.matchMedia("(max-width: 767px)").matches) {
      this.layersSidebarTarget.setAttribute("aria-hidden", (!open).toString())
    } else {
      this.layersSidebarTarget.removeAttribute("aria-hidden")
    }
  }

  openLegend(event) {
    event?.preventDefault()
    const trigger = this.element.querySelector("#map-legend-dialog-root")
    trigger?.click()
  }

  selectCategory(event) {
    const button = event.currentTarget
    const category = button.dataset.category
    if (!category) return

    this.activeCategory = category

    this.categoryChipTargets.forEach((chip) => {
      const active = chip.dataset.category === category
      chip.classList.toggle("layer-category-chip--active", active)
      chip.setAttribute("aria-selected", active.toString())
    })

    this.filterLayers()
  }

  initializeCategoryFilter() {
    if (!this.hasCategoryChipTarget) return

    const chipsRoot = this.categoryChipTargets[0]?.closest(".layer-category-chips")
    const defaultCategory = chipsRoot?.dataset.defaultCategory ||
      this.categoryChipTargets[0]?.dataset.category

    if (!defaultCategory) return

    this.activeCategory = defaultCategory
    this.categoryChipTargets.forEach((chip) => {
      const active = chip.dataset.category === defaultCategory
      chip.classList.toggle("layer-category-chip--active", active)
      chip.setAttribute("aria-selected", active.toString())
    })
    this.filterLayers()
  }

  invalidateMapSize() {
    if (!this.map) return

    requestAnimationFrame(() => this.map.invalidateSize(true))
  }

  syncPanelToggleState(panel) {
    const control = panel?.querySelector('[aria-controls="map-layers-panel-body"]')
    if (!control) return

    const collapsed = panel.classList.contains("map-ui-panel--collapsed")
    const label = collapsed ? this.t("panel.expand") : this.t("panel.collapse")

    control.setAttribute("aria-expanded", (!collapsed).toString())
    control.setAttribute("aria-label", label)
  }

  syncPanelToggleStates() {
    if (this.hasLayersPanelTarget) this.syncPanelToggleState(this.layersPanelTarget)
  }

  filterLayers() {
    if (!this.hasLayerSearchInputTarget) return

    const query = this.normalizeSearchQuery(this.layerSearchInputTarget.value)
    const hasQuery = query.length > 0
    const category = this.activeCategory
    let visibleItemCount = 0

    this.layerSearchItemTargets.forEach((item) => {
      const text = this.normalizeSearchQuery(item.dataset.searchText || "")
      const itemCategory = item.dataset.category || ""
      // While searching, match across all categories so station names are findable.
      const categoryMatch = hasQuery || !category || itemCategory === category
      const match = categoryMatch && (!hasQuery || text.includes(query))

      item.classList.toggle("hidden", !match)
      if (match) visibleItemCount += 1
    })

    this.layerSearchGroupTargets.forEach((group) => {
      const groupText = this.normalizeSearchQuery(group.dataset.searchText || "")
      const groupCategory = group.dataset.category || ""
      const categoryMatch = hasQuery || !category || groupCategory === category
      const groupMatch = hasQuery && groupText.includes(query)
      const childMatch = Array.from(
        group.querySelectorAll("[data-map-target=\"layerSearchItem\"]")
      ).some((item) => !item.classList.contains("hidden"))
      const visible = categoryMatch && (!hasQuery || groupMatch || childMatch)

      group.classList.toggle("hidden", !visible)
    })

    if (this.hasLayerSearchClearTarget) {
      this.layerSearchClearTarget.classList.toggle("hidden", !hasQuery)
    }

    if (this.hasLayerSearchEmptyTarget) {
      const showEmpty = visibleItemCount === 0 && (hasQuery || Boolean(category))

      this.layerSearchEmptyTarget.classList.toggle("hidden", !showEmpty)
    }
  }

  clearLayerSearch() {
    if (!this.hasLayerSearchInputTarget) return

    this.layerSearchInputTarget.value = ""
    this.filterLayers()
    this.layerSearchInputTarget.focus()
  }

  expandLayerSearchGroup(group) {
    const collapsible = this.application.getControllerForElementAndIdentifier(
      group,
      "ruby-ui--collapsible"
    )
    if (collapsible) collapsible.openValue = true
  }

  collapseLayerSearchGroup(group) {
    const collapsible = this.application.getControllerForElementAndIdentifier(
      group,
      "ruby-ui--collapsible"
    )
    if (collapsible) collapsible.openValue = false
  }

  normalizeSearchQuery(value) {
    return value.trim().toLowerCase().replace(/\s+/g, " ")
  }

  stopCheckboxEvent(event) {
    event.stopPropagation()
  }

  async selectRoute(event) {
    const routeId = event.params.routeId
    if (!routeId) return

    window.location.assign(`/routes/${encodeURIComponent(routeId)}`)
  }

  syncRouteSelectionUI() {
    if (!this.hasLayerSearchItemTarget) return

    this.layerSearchItemTargets.forEach((item) => {
      const routeId = item.dataset.routeId
      const selected = Boolean(routeId) && routeId === this.selectedRouteId

      item.classList.toggle("route-search-item--selected", selected)
      item.setAttribute("aria-current", selected ? "true" : "false")
    })
  }

  async displayRouteStops(routeId) {
    if (!this.hasRouteStopsListTarget) return

    const route = this.findRoute(routeId)
    let sections = []

    try {
      sections = await this.collectStationsForRoute(routeId)
    } catch (error) {
      console.error("Failed to load stations for route", routeId, error)
    }

    this.renderRouteStopsPanel(route, sections)
    if (this.hasRouteBrowserTarget) this.setRouteBrowserStopsOpen(true)
  }

  async collectStationsForRoute(routeId) {
    if (routeId === "airport_mrt") {
      return this.collectAirportMrtCommuterStationSections()
    }

    if (routeId === "airport_mrt_express") {
      return this.collectAirportMrtExpressStationSections()
    }

    const manifestRoute = this.findRoute(routeId)
    const routes = this.routesToLoad(routeId)
    const sections = []

    for (const route of routes) {
      const url = route.file || route.url
      if (!url) continue

      const data = await this.fetchGeoJSON(url)
      sections.push(...this.buildStationSectionsFromGeoJSON(data, manifestRoute, routeId))
    }

    return this.mergeStationSections(sections)
  }

  async collectAirportMrtCommuterStationSections() {
    const commuterRoute = this.findRoute("airport_mrt")
    if (!commuterRoute?.file) return []

    const commuterData = await this.fetchGeoJSON(commuterRoute.file)
    return this.buildAirportMrtCommuterStationSections(commuterData)
  }

  async collectAirportMrtExpressStationSections() {
    const expressRoute = this.findRoute("airport_mrt_express")
    if (!expressRoute?.file) return []

    const expressData = await this.fetchGeoJSON(expressRoute.file)
    return this.buildAirportMrtExpressStationSections(expressData)
  }

  buildAirportMrtCommuterStationSections(commuterGeojson) {
    const routeId = "airport_mrt"
    const manifestRoute = this.findRoute(routeId)
    const commuterStations = this.extractPassengerStationFeatures(commuterGeojson, routeId)
    const orderedCommuter = this.sortStationsForRoute(
      commuterStations,
      manifestRoute?.ref,
      commuterGeojson
    )

    return [
      { label: this.t("sections.commuter"), stations: orderedCommuter }
    ].filter((section) => section.stations.length > 0)
  }

  buildAirportMrtExpressStationSections(expressGeojson) {
    const routeId = "airport_mrt_express"
    const expressStations = this.extractPassengerStationFeatures(expressGeojson, routeId)
    const orderedExpress = this.sortAirportMrtExpressStationsForList(expressStations)

    return [
      { label: this.t("sections.express"), stations: orderedExpress }
    ].filter((section) => section.stations.length > 0)
  }

  sortAirportMrtExpressStationsForList(stations) {
    const order = Array.from(AIRPORT_MRT_EXPRESS_STOP_REFS)

    return stations.slice().sort((left, right) => {
      const leftIndex = order.indexOf(this.airportMrtExpressOrderRef(left.ref))
      const rightIndex = order.indexOf(this.airportMrtExpressOrderRef(right.ref))

      if (leftIndex >= 0 && rightIndex >= 0) return leftIndex - rightIndex
      if (leftIndex >= 0) return -1
      if (rightIndex >= 0) return 1

      return this.compareStationRefsOnRoute(left.ref, right.ref, "A")
    })
  }

  airportMrtExpressOrderRef(ref) {
    const parts = this.transferStationRefs(ref)
    return parts.find((part) => AIRPORT_MRT_EXPRESS_STOP_REFS.has(part)) || parts[0] || ref
  }

  buildStationSectionsFromGeoJSON(geojson, manifestRoute, routeId) {
    if (manifestRoute?.id === "danhai_lrt") {
      return this.buildDanhaiStationSections(geojson, routeId)
    }

    if (manifestRoute?.id === "taoyuan_airport_skytrain") {
      return this.buildSkytrainStationSections(geojson, routeId)
    }

    const stations = this.extractPassengerStationFeatures(geojson, routeId)
    const ordered = this.sortStationsForRoute(stations, manifestRoute?.ref, geojson)

    return [ { label: null, stations: ordered } ]
  }

  buildDanhaiStationSections(geojson, routeId) {
    const stations = this.extractPassengerStationFeatures(geojson, routeId)

    return [
      { key: "lushan", label: this.t("sections.lushan") },
      { key: "lanhai", label: this.t("sections.lanhai") }
    ].map(({ key, label }) => {
      const segmentStations = stations.filter((station) => station.segment === key)
      return { label, stations: this.sortDanhaiStationsForList(segmentStations, key) }
    }).filter((section) => section.stations.length > 0)
  }

  buildSkytrainStationSections(geojson, routeId) {
    const activeStations = this.extractPassengerStationFeatures(geojson, routeId)
    const suspendedStations = this.extractSuspendedStationFeatures(geojson, routeId)

    return [
      { key: "north", label: this.t("sections.skytrain_north"), includeSuspended: false },
      { key: "south", label: this.t("sections.skytrain_south"), includeSuspended: true }
    ].map(({ key, label, includeSuspended }) => {
      const active = activeStations.filter((station) => station.segment === key)
      const suspended = includeSuspended
        ? suspendedStations.filter((station) => station.segment === key)
        : []
      const stations = [ ...active, ...suspended ]

      return { label, stations: this.sortSkytrainStationsForList(stations, key) }
    }).filter((section) => section.stations.length > 0)
  }

  sortSkytrainStationsForList(stations, segment) {
    const order = segment === "north" ? SKYTRAIN_NORTH_STATION_ORDER : SKYTRAIN_SOUTH_STATION_ORDER

    return stations.slice().sort((left, right) => {
      const leftIndex = order.indexOf(left.ref)
      const rightIndex = order.indexOf(right.ref)

      if (leftIndex >= 0 && rightIndex >= 0) return leftIndex - rightIndex
      if (leftIndex >= 0) return -1
      if (rightIndex >= 0) return 1

      return this.compareStationRefsOnRoute(left.ref, right.ref, "ST")
    })
  }

  sortDanhaiStationsForList(stations, segment) {
    const sortKey = (station) => {
      const ref = station.ref
      if (DANHAI_SHARED_STATION_REFS.has(ref)) return parseInt(ref.slice(1), 10)

      if (segment === "lanhai") {
        const lanhaiIndex = DANHAI_LANHAI_STATION_ORDER.indexOf(ref)
        if (lanhaiIndex >= 0) return 10 + lanhaiIndex
      }

      const match = ref.match(/V(\d+)/i)
      return match ? parseInt(match[1], 10) : 99
    }

    return stations.slice().sort((left, right) => sortKey(left) - sortKey(right))
  }

  extractSuspendedStationFeatures(geojson, routeId) {
    return (geojson.features || [])
      .filter((feature) => {
        if (feature.properties?.feature_type !== "station") return false
        if (feature.properties?.passenger_service !== false) return false

        const route = this.findRoute(routeId)
        const ref = feature.properties?.ref || ""

        return this.stationRefMatchesRoute(ref, route?.ref, routeId)
      })
      .map((feature) => {
        const ref = feature.properties?.ref || ""
        const coords = feature.geometry?.coordinates
        const latlng = Array.isArray(coords) && coords.length >= 2
          ? [ coords[1], coords[0] ]
          : null

        if (ref && latlng) this.rememberStationCoords(routeId, ref, latlng)

        return {
          ref,
          name: this.routeStopDisplayName(feature),
          nameEn: feature.properties?.name_en,
          segment: feature.properties?.segment,
          latlng
        }
      })
      .filter((station) => station.ref)
  }

  extractPassengerStationFeatures(geojson, routeId) {
    return (geojson.features || [])
      .filter((feature) => this.isRouteStopListStation(feature, routeId))
      .map((feature) => {
        const ref = feature.properties?.ref || ""
        const coords = feature.geometry?.coordinates
        const latlng = Array.isArray(coords) && coords.length >= 2
          ? [ coords[1], coords[0] ]
          : null

        if (ref && latlng) this.rememberStationCoords(routeId, ref, latlng)

        return {
          ref,
          name: this.routeStopDisplayName(feature),
          nameEn: feature.properties?.name_en,
          segment: feature.properties?.segment,
          latlng
        }
      })
      .filter((station) => station.ref)
  }

  isRouteStopListStation(feature, routeId) {
    if (routeId === "maokong_gondola" && feature.properties?.feature_type === "angle_station") {
      return true
    }

    if (!this.isPassengerStationFeature(feature)) return false

    const route = this.findRoute(routeId)
    const ref = feature.properties?.ref || ""

    return this.stationRefMatchesRoute(ref, route?.ref, routeId)
  }

  stationRefMatchesRoute(stationRef, routeRef, routeId) {
    if (!stationRef) return false
    if (!routeRef) return true

    const sortKey = this.stationSortKeyForRoute(stationRef, routeRef)

    if (routeRef === "MG" || routeId === "maokong_gondola") {
      return /^G[1-6]$/i.test(sortKey)
    }

    if (routeRef === "HSR" || routeId === "taiwan_hsr") {
      return /^\d{1,3}$/.test(sortKey)
    }

    if (this.isTraRoute(routeId)) {
      return /^\d{3,4}$/.test(sortKey)
    }

    // Songshan–Xindian / Xiaobitan use zero-padded G01… refs; bare G1–G6 are Maokong.
    if (routeRef === "G") {
      return /^G\d{2}/i.test(sortKey)
    }

    return new RegExp(`^${routeRef}\\d`, "i").test(sortKey)
  }

  routeStopDisplayName(feature) {
    const name = this.featureDisplayName(feature)
    const note = feature.properties?.note

    if (feature.properties?.feature_type === "angle_station" && note) {
      return `${name}${this.t("stops.no_passenger")}`
    }

    if (feature.properties?.passenger_service === false) {
      return `${name}${this.t("stops.suspended")}`
    }

    return name
  }

  isPassengerStationFeature(feature) {
    const type = feature.properties?.feature_type
    if (type === "station") return feature.properties?.passenger_service !== false
    if (type === "angle_station") return feature.properties?.passenger_service !== false

    return false
  }

  rememberStationCoords(routeId, ref, latlng) {
    if (!this.stationCoordsByRouteRef[routeId]) {
      this.stationCoordsByRouteRef[routeId] = {}
    }

    this.stationCoordsByRouteRef[routeId][ref] = latlng
  }

  sortStationsForRoute(stations, routeRef, geojson) {
    const lineStrings = this.routeLineStringsFromGeoJSON(geojson)

    if (lineStrings.length > 0 && this.shouldOrderStationsAlongRoute(routeRef, stations)) {
      return this.sortStationsAlongLineStrings(stations, lineStrings)
    }

    return stations.slice().sort((left, right) => {
      return this.compareStationRefsOnRoute(left.ref, right.ref, routeRef)
    })
  }

  shouldOrderStationsAlongRoute(routeRef, stations) {
    if (!routeRef) return true

    const onRoute = (ref) => this.stationRefMatchesRoute(ref, routeRef, null)

    const onLineCount = stations.filter((station) => onRoute(station.ref)).length
    const offLineCount = stations.length - onLineCount

    if (offLineCount > 0 && onLineCount > 0) return true

    const hasNumericRefs = stations.some((station) => /^\d/.test(station.ref))

    return onLineCount === 0 && !hasNumericRefs
  }

  stationSortKeyForRoute(stationRef, routeRef) {
    if (!stationRef) return ""

    const parts = stationRef.split(";").map((part) => part.trim()).filter(Boolean)
    if (!routeRef) return parts[0] || stationRef

    if (routeRef === "MG") {
      const gondolaPart = parts.find((part) => /^G\d/i.test(part))
      if (gondolaPart) return gondolaPart
    }

    const routePart = parts.find((part) => new RegExp(`^${routeRef}\\d`, "i").test(part))
    if (routePart) return routePart

    if (parts.every((part) => /^\d/.test(part))) return parts[0]

    return parts[0] || stationRef
  }

  compareStationRefsOnRoute(leftRef, rightRef, routeRef) {
    const left = this.stationRefSortKey(this.stationSortKeyForRoute(leftRef, routeRef))
    const right = this.stationRefSortKey(this.stationSortKeyForRoute(rightRef, routeRef))

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

    return String(leftRef).localeCompare(String(rightRef))
  }

  sortStationsAlongLineStrings(stations, lineStrings) {
    const primaryLine = lineStrings.reduce((longest, current) => {
      return current.length > longest.length ? current : longest
    }, [])

    return stations.slice().sort((left, right) => {
      if (!left.latlng || !right.latlng) return 0

      const leftIndex = this.chainIndexForPoint(left.latlng[0], left.latlng[1], primaryLine)
      const rightIndex = this.chainIndexForPoint(right.latlng[0], right.latlng[1], primaryLine)
      return leftIndex - rightIndex
    })
  }

  chainIndexForPoint(lat, lon, coordinates) {
    let bestIndex = 0
    let bestDistance = Infinity

    for (let segmentIndex = 0; segmentIndex < coordinates.length - 1; segmentIndex += 1) {
      const start = coordinates[segmentIndex]
      const finish = coordinates[segmentIndex + 1]
      const projection = this.projectLonLatOnSegment(lon, lat, start, finish)
      const index = segmentIndex + projection.progress

      if (projection.distance < bestDistance) {
        bestDistance = projection.distance
        bestIndex = index
      }
    }

    return bestIndex
  }

  projectLonLatOnSegment(px, py, start, finish) {
    const [ x1, y1 ] = start
    const [ x2, y2 ] = finish
    const dx = x2 - x1
    const dy = y2 - y1
    const lengthSquared = (dx * dx) + (dy * dy)

    let progress = 0
    if (lengthSquared > 0) {
      progress = ((px - x1) * dx + (py - y1) * dy) / lengthSquared
      progress = Math.max(0, Math.min(1, progress))
    }

    const projectedX = x1 + (progress * dx)
    const projectedY = y1 + (progress * dy)
    const distance = ((px - projectedX) ** 2) + ((py - projectedY) ** 2)

    return { progress, distance, projectedX, projectedY }
  }

  routeLineStringsFromGeoJSON(geojson) {
    return (geojson.features || [])
      .filter((feature) => feature.properties?.feature_type === "route")
      .map((feature) => feature.geometry?.coordinates)
      .filter((coordinates) => Array.isArray(coordinates) && coordinates.length >= 2)
  }

  mergeStationSections(sections) {
    const merged = []
    const seen = new Set()

    sections.forEach((section) => {
      const stations = []

      section.stations.forEach((station) => {
        const key = this.stationListKey(station)
        if (seen.has(key)) return

        seen.add(key)
        stations.push(station)
      })

      if (stations.length > 0) merged.push({ label: section.label, stations })
    })

    return merged
  }

  stationListKey(station) {
    if (station.segment) return `${station.ref}:${station.segment}`

    return station.ref
  }

  renderRouteStopsPanel(route, sections) {
    if (this.hasRouteStopsTitleTarget) {
      this.routeStopsTitleTarget.textContent = this.routeDisplayName(route) || this.t("stops.title_fallback")
    }

    const stationCount = sections.reduce((total, section) => total + section.stations.length, 0)

    if (this.hasRouteStopsMetaTarget) {
      const ref = route?.ref ? ` · ${route.ref}` : ""
      this.routeStopsMetaTarget.textContent = stationCount > 0
        ? `${this.t("stops.count", { count: stationCount })}${ref}`
        : ""
    }

    if (!this.hasRouteStopsListTarget) return

    this.routeStopsListTarget.replaceChildren()

    if (stationCount === 0) {
      if (this.hasRouteStopsEmptyTarget) this.routeStopsEmptyTarget.classList.remove("hidden")
      return
    }

    if (this.hasRouteStopsEmptyTarget) this.routeStopsEmptyTarget.classList.add("hidden")

    let sequence = 0

    sections.forEach((section) => {
      if (section.label) {
        const heading = document.createElement("li")
        heading.className = "route-stops-section-heading"
        heading.textContent = section.label
        this.routeStopsListTarget.append(heading)
      }

      section.stations.forEach((station) => {
        sequence += 1
        this.routeStopsListTarget.append(this.buildRouteStopItem(route, station, sequence))
      })
    })
  }

  formatRouteStopRef(ref, route) {
    if (!ref) return ref

    if (route?.id === "taiwan_hsr" && /^\d{1,2}$/.test(ref)) {
      return ref.padStart(2, "0")
    }

    return ref
  }

  stationRefsForRouteStop(stationRef, route) {
    const parts = this.transferStationRefs(stationRef)
    if (parts.length <= 1) {
      return { primary: stationRef, secondary: null, orderedParts: parts }
    }

    const routeRef = route?.ref
    const routeId = route?.id
    const primary = parts.find((ref) => this.stationRefMatchesRoute(ref, routeRef, routeId)) || parts[0]
    const secondary = parts.find((ref) => ref !== primary) || null
    const orderedParts = secondary ? [ primary, secondary ] : [ primary ]

    return { primary, secondary, orderedParts }
  }

  buildRouteStopItem(route, station, sequence) {
    const item = document.createElement("li")
    const button = document.createElement("button")
    const isInSystemTransfer = this.isInSystemInStationTransferRef(station.ref, route?.id)
    const isCrossSystemTransfer = this.isCrossSystemTransferRef(station.ref)
    const refsForStop = this.stationRefsForRouteStop(station.ref, route)

    button.type = "button"
    button.className = "route-stop-item"
    if (isInSystemTransfer) button.classList.add("route-stop-item--transfer")
    if (isCrossSystemTransfer) button.classList.add("route-stop-item--cross-system-transfer")
    button.dataset.action = "click->map#focusRouteStop"
    button.dataset.mapRouteIdParam = route?.id || this.selectedRouteId
    button.dataset.mapRefParam = station.ref

    const indexEl = document.createElement("span")
    indexEl.className = "route-stop-item__index"
    indexEl.textContent = this.formatRouteStopRef(refsForStop.primary, route) || String(sequence)
    if (isInSystemTransfer || isCrossSystemTransfer) indexEl.title = station.ref

    const swatchEl = document.createElement("span")
    swatchEl.className = "route-stop-item__swatch"
    swatchEl.setAttribute("aria-hidden", "true")
    if (isInSystemTransfer) {
      swatchEl.append(this.buildRouteStopTransferMarker(route, station.ref))
    } else if (isCrossSystemTransfer) {
      swatchEl.append(this.buildRouteStopCrossSystemTransferMarker())
    }

    const nameEl = document.createElement("span")
    nameEl.className = "route-stop-item__name"
    nameEl.textContent = this.stationDisplayName(station)

    const refEl = document.createElement("span")
    refEl.className = "route-stop-item__ref"
    refEl.textContent = isInSystemTransfer ? (this.formatRouteStopRef(refsForStop.secondary, route) || "") : ""
    if (isInSystemTransfer || isCrossSystemTransfer) refEl.title = station.ref

    button.append(indexEl, swatchEl, nameEl, refEl)
    item.append(button)
    return item
  }

  buildRouteStopTransferMarker(route, stationRef) {
    const marker = document.createElement("span")
    marker.className = "route-stop-item__transfer-marker transfer-station-marker"

    const { orderedParts } = this.stationRefsForRouteStop(stationRef, route)

    orderedParts.slice(0, 2).forEach((part) => {
      const half = document.createElement("span")
      half.className = "transfer-station-marker__half"
      half.style.backgroundColor = this.colorForStationRef(part) || "#666666"
      marker.append(half)
    })

    return marker
  }

  buildRouteStopCrossSystemTransferMarker() {
    const marker = document.createElement("span")
    marker.className = "route-stop-item__transfer-line"
    return marker
  }

  setRouteBrowserStopsOpen(open) {
    if (!this.hasRouteBrowserTarget) return

    this.routeBrowserTarget.classList.toggle("route-browser--stops-open", open)

    if (this.hasRouteStopsPanelTarget) {
      this.routeStopsPanelTarget.classList.toggle("hidden", !open)
      this.routeStopsPanelTarget.classList.toggle("flex", open)
    }
  }

  focusRouteStop(event) {
    const routeId = event.params.routeId
    const ref = event.params.ref
    const latlng = this.stationCoordsByRouteRef[routeId]?.[ref]

    if (latlng && this.map) {
      this.map.setView(latlng, Math.max(this.map.getZoom(), 14))
    }

    this.openStationBoard({ routeId, ref, name: this.stationNameForRef(ref, routeId) || ref })
  }

  fastBasemapUrl() {
    return this.cartoBasemapUrl()
  }

  cartoBasemapUrl() {
    const dark = document.documentElement.classList.contains("dark")
    return dark ? CARTO_DARK_BASEMAP_URL : CARTO_LIGHT_BASEMAP_URL
  }

  readBasemapStyle() {
    try {
      const stored = window.localStorage?.getItem(BASEMAP_MODE_STORAGE_KEY)
      if (stored === "sat" || stored === "carto" || stored === "nlsc") return stored

      const legacyMode = window.localStorage?.getItem(LEGACY_BASEMAP_MODE_STORAGE_KEY)
      if (legacyMode === "sat") return "sat"

      const legacyNlsc = window.localStorage?.getItem(LEGACY_NLSC_ENABLED_STORAGE_KEY)
      if (legacyNlsc === "0") return "carto"

      return "nlsc"
    } catch (_error) {
      return "nlsc"
    }
  }

  usesNlscPrimary() {
    return this.basemapStyle === "nlsc"
  }

  primaryBasemapUrl() {
    if (this.basemapStyle === "sat") return ESRI_SAT_BASEMAP_URL
    if (this.basemapStyle === "nlsc") return NLSC_BASEMAP_URL
    return this.cartoBasemapUrl()
  }

  primaryBasemapOptions() {
    if (this.basemapStyle === "sat") {
      return {
        maxZoom: 19,
        attribution: ESRI_SAT_BASEMAP_ATTRIBUTION
      }
    }

    if (this.basemapStyle === "nlsc") {
      return {
        maxZoom: 19,
        maxNativeZoom: 19,
        attribution: NLSC_BASEMAP_ATTRIBUTION
      }
    }

    return {
      subdomains: "abcd",
      maxZoom: 20,
      attribution: CARTO_BASEMAP_ATTRIBUTION
    }
  }

  syncPrimaryBasemap() {
    if (!this.tileLayer) return

    const options = this.primaryBasemapOptions()
    this.tileLayer.setUrl(this.primaryBasemapUrl())
    if (options.attribution) this.tileLayer.options.attribution = options.attribution
    if (options.maxZoom) this.tileLayer.options.maxZoom = options.maxZoom
    if (options.maxNativeZoom) {
      this.tileLayer.options.maxNativeZoom = options.maxNativeZoom
    } else {
      delete this.tileLayer.options.maxNativeZoom
    }
    if (options.subdomains) {
      this.tileLayer.options.subdomains = options.subdomains
    } else {
      delete this.tileLayer.options.subdomains
    }
    this.syncPrimaryBasemapClass()
  }

  syncPrimaryBasemapClass() {
    const container = this.tileLayer?.getContainer?.()
    if (!container) return

    const dark = document.documentElement.classList.contains("dark")
    container.classList.toggle("nlsc-basemap-tiles", this.usesNlscPrimary())
    container.classList.toggle("nlsc-basemap-tiles--dark", this.usesNlscPrimary() && dark)
  }

  syncBasemapSelect() {
    if (!this.hasBasemapSelectTarget) return

    this.basemapSelectTarget.value = this.basemapStyle
  }

  setBasemapStyle(event) {
    const style = event?.target?.value
    if (!style || style === this.basemapStyle) return
    if (style !== "nlsc" && style !== "carto" && style !== "sat") return

    this.basemapStyle = style

    try {
      window.localStorage?.setItem(BASEMAP_MODE_STORAGE_KEY, this.basemapStyle)
    } catch (_error) {
      // ignore storage failures
    }

    this.syncPrimaryBasemap()
    this.syncBasemapSelect()
    this.applyRouteEmphasis()
    this.map?.getContainer()?.classList.toggle("map-basemap--satellite", this.basemapStyle === "sat")
  }

  applyThemeBasemap() {
    if (this.basemapStyle === "carto") this.syncPrimaryBasemap()
    this.syncPrimaryBasemapClass()
    this.applyRouteEmphasis()
  }

  watchThemeChanges() {
    this.applyThemeBasemap()
    this.map?.getContainer()?.classList.toggle("map-basemap--satellite", this.basemapStyle === "sat")

    this.themeObserver = new MutationObserver(() => this.applyThemeBasemap())
    this.themeObserver.observe(document.documentElement, {
      attributes: true,
      attributeFilter: [ "class" ]
    })
  }

  async setAllMetroLayersVisible(visible, { fitBounds = false } = {}) {
    const allMetroCheckbox = this.checkboxForLayer("all_metro")
    if (allMetroCheckbox) allMetroCheckbox.checked = visible

    await this.setRouteLayersVisible(this.allMetroRouteIds(), visible, {
      fitBounds,
      afterSync: () => {
        METRO_SYSTEM_IDS.forEach((systemId) => this.syncMetroSystemCheckbox(systemId))
        this.syncAllMetroCheckbox()
        this.syncAllTransitCheckbox()
      }
    })
  }

  async setAllTraLayersVisible(visible, { fitBounds = false } = {}) {
    this.traToggleCheckboxes().forEach((checkbox) => {
      checkbox.checked = visible
    })

    await this.setRouteLayersVisible(this.allTraRouteIds(), visible, {
      fitBounds,
      afterSync: () => {
        this.syncManifestSystemCheckbox("tra")
        this.syncAllTraCheckbox()
        this.syncAllTransitCheckbox()
      }
    })
  }

  async setAllTransitLayersVisible(visible, { fitBounds = false } = {}) {
    if (visible) {
      const allMetroCheckbox = this.checkboxForLayer("all_metro")
      if (allMetroCheckbox) allMetroCheckbox.checked = true
    }

    await this.setRouteLayersVisible(this.allTransitRouteIds(), visible, {
      fitBounds,
      afterSync: () => this.syncAllTransitCheckboxes()
    })
  }

  async setRouteLayersVisible(routeIds, visible, { fitBounds = false, afterSync = null } = {}) {
    if (routeIds.length === 0) {
      if (!visible) this.map?.fitBounds(LEAFLET_BOUNDS)
      return
    }

    this.setLayerControlsDisabled(true)

    try {
      if (visible) {
        await this.mapPool(routeIds, LAYER_LOAD_CONCURRENCY, async (routeId) => {
          if (this.booting) {
            const route = this.findRoute(routeId)
            this.startBootTask(`route:${routeId}`, this.routeDisplayName(route) || routeId)
          }
          try {
            await this.showLayer(routeId, { fitBounds: false, manageControl: false })
            if (this.booting) this.finishBootTask(`route:${routeId}`)
          } catch (error) {
            if (this.booting) this.finishBootTask(`route:${routeId}`, "error")
            throw error
          }
        })

        afterSync?.()

        if (fitBounds) {
          this.fitVisibleRouteBounds()
        }
      } else {
        routeIds.forEach((routeId) => {
          this.hideLayerWithCheckbox(routeId, this.checkboxForLayer(routeId))
        })

        afterSync?.()
      }

      this.updateOutOfStationTransfers()
      this.updateMetroDepots()
      if (this.simulationAt) {
        this.ensureScheduleSnapshots(this.visibleRouteLayerIds())
        this.scheduleVehicleRefresh()
        this.scheduleShareUrlUpdate()
      }
    } finally {
      this.setLayerControlsDisabled(false)
    }
  }

  async mapPool(items, concurrency, worker) {
    const queue = items.slice()
    const runners = Array.from({ length: Math.min(concurrency, Math.max(queue.length, 1)) }, async () => {
      while (queue.length > 0) {
        const item = queue.shift()
        if (item === undefined) return
        await worker(item)
      }
    })

    await Promise.all(runners)
  }

  setLayerControlsDisabled(disabled) {
    if (!disabled && this.booting) return

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

  routeIdsForSystem(systemId) {
    return (this.routesManifest[systemId] || [])
      .filter((route) => route.id)
      .map((route) => route.id)
  }

  allMetroRouteIds() {
    const ids = []

    METRO_SYSTEM_IDS.forEach((systemId) => {
      ids.push(...this.routeIdsForSystem(systemId))
    })

    return ids
  }

  allTraRouteIds() {
    return this.routeIdsForSystem("tra")
  }

  traToggleCheckboxes() {
    return [ "all_tra", "tra" ]
      .map((layerId) => this.checkboxForLayer(layerId))
      .filter(Boolean)
  }

  allTransitRouteIds() {
    return this.routeLayerIds()
  }

  transitSystemIds() {
    return [ "tra", "hsr", "sugar_railway", "ferry", "other" ]
  }

  isTraRoute(routeId) {
    return (this.routesManifest.tra || []).some((route) => route.id === routeId)
  }

  metroSystemForRoute(routeId) {
    for (const systemId of METRO_SYSTEM_IDS) {
      if (this.routeIdsForSystem(systemId).includes(routeId)) return systemId
    }

    return null
  }

  manifestSystemForRoute(routeId) {
    const metroSystemId = this.metroSystemForRoute(routeId)
    if (metroSystemId) return metroSystemId

    for (const systemId of this.transitSystemIds()) {
      if (this.routeIdsForSystem(systemId).includes(routeId)) return systemId
    }

    return null
  }

  syncMetroSystemCheckbox(systemId) {
    const checkbox = this.checkboxForLayer(systemId)
    if (!checkbox) return

    const routeIds = this.routeIdsForSystem(systemId)
    if (routeIds.length === 0) return

    const allOn = routeIds.every((routeId) => this.layerVisible[routeId])
    const anyOn = routeIds.some((routeId) => this.layerVisible[routeId])

    checkbox.checked = allOn
    checkbox.indeterminate = anyOn && !allOn
  }

  syncAllMetroCheckbox() {
    const checkbox = this.checkboxForLayer("all_metro")
    if (!checkbox) return

    this.syncRouteGroupCheckbox(checkbox, this.allMetroRouteIds())
  }

  syncAllTransitCheckbox() {
    const checkbox = this.checkboxForLayer("all_transit")
    if (!checkbox) return

    this.syncRouteGroupCheckbox(checkbox, this.allTransitRouteIds())
  }

  syncAllTraCheckbox() {
    const routeIds = this.allTraRouteIds()
    if (routeIds.length === 0) return

    this.traToggleCheckboxes().forEach((checkbox) => {
      this.syncRouteGroupCheckbox(checkbox, routeIds)
    })
  }

  syncRouteGroupCheckbox(checkbox, routeIds) {
    if (routeIds.length === 0) return

    const allOn = routeIds.every((routeId) => this.layerVisible[routeId])
    const anyOn = routeIds.some((routeId) => this.layerVisible[routeId])

    checkbox.checked = allOn
    checkbox.indeterminate = anyOn && !allOn
  }

  syncAllTransitCheckboxes() {
    METRO_SYSTEM_IDS.forEach((systemId) => this.syncMetroSystemCheckbox(systemId))
    this.transitSystemIds().forEach((systemId) => this.syncManifestSystemCheckbox(systemId))
    this.syncAllMetroCheckbox()
    this.syncAllTraCheckbox()
    this.syncAllTransitCheckbox()
  }

  syncManifestSystemCheckbox(systemId) {
    const checkbox = this.checkboxForLayer(systemId)
    if (!checkbox) return

    this.syncRouteGroupCheckbox(checkbox, this.routeIdsForSystem(systemId))
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

    const routeIds = this.routeIdsForSystem(systemId)
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
      if (systemId === "tra") this.syncAllTraCheckbox()
      this.syncAllMetroCheckbox()
      this.syncAllTransitCheckbox()
      this.updateOutOfStationTransfers()
    } finally {
      this.setLayerControlsDisabled(false)
    }
  }

  async toggleAllTra(event) {
    event.preventDefault()

    const checkbox = event.currentTarget
    const visible = checkbox.checked

    if (!this.mapReady || !this.map) {
      checkbox.checked = false
      return
    }

    if (this.allTraRouteIds().length === 0) {
      checkbox.checked = false
      return
    }

    await this.setAllTraLayersVisible(visible, { fitBounds: visible })
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
      const name = this.featureDisplayName(feature)

      this.coordinateIndexRefs(routeId, ref).forEach((stationRef) => {
        this.stationCoordinatesByKey[this.stationKey(routeId, stationRef)] = latlng
        if (name) this.stationNameByKey[this.stationKey(routeId, stationRef)] = name
      })
      this.transferStationRefs(ref).forEach((stationRef) => {
        if (name) this.stationNameByKey[this.stationKey(routeId, stationRef)] ||= name
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

        this.coordinateIndexRefs(route.id, feature.properties?.ref).forEach((stationRef) => {
          delete this.stationCoordinatesByKey[this.stationKey(route.id, stationRef)]
          delete this.stationNameByKey[this.stationKey(route.id, stationRef)]
        })
        this.transferStationRefs(feature.properties?.ref).forEach((stationRef) => {
          delete this.stationNameByKey[this.stationKey(route.id, stationRef)]
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
      const latlngs = (transfer.endpoints || [])
        .map((endpoint) => this.visibleTransferEndpointLatLng(endpoint))
        .filter(Boolean)

      if (latlngs.length < 2) return
      if (latlngs[0].equals?.(latlngs[1])) return

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

    this.updateCrossSystemInStationTransfers()
    this.updateInStationTransferMarkers()
    this.updateMetroDepots()
  }

  isRouteLayerVisible(routeId) {
    if (!routeId) return false

    return Boolean(this.layerVisible[routeId])
  }

  // Resolve a transfer end on any visible line that carries that station ref.
  // Catalog `routes` is a typical pair (e.g. pingtung + red); TRA 高雄 is also
  // on western_trunk_south, so that layer plus the MRT should still draw.
  visibleTransferEndpointLatLng(endpoint) {
    if (!endpoint?.ref) return null

    if (endpoint.route_id && this.layerVisible[endpoint.route_id]) {
      const direct = this.stationLatLng(endpoint.route_id, endpoint.ref)
      if (direct) return direct
    }

    for (const routeId of this.visibleRouteLayerIds()) {
      const latlng = this.stationLatLng(routeId, endpoint.ref)
      if (latlng) return latlng
    }

    return null
  }

  updateMetroDepots() {
    const L = window.L
    const group = this.metroDepotGroup

    if (!group || !this.map) return

    group.clearLayers()

    this.metroDepots.forEach((depot) => {
      if (depot.lon == null || depot.lat == null) return
      if (!depot.routes?.some((routeId) => this.isRouteLayerVisible(routeId))) return

      const color = this.depotDisplayColor(depot) || "#64748B"
      const marker = this.metroDepotMarkerAt(L.latLng(depot.lat, depot.lon), color)

      this.renderDepotTrackLinks(depot, color)

      const gradeNote = depot.grade ? `<br><span style="opacity:0.8">${this.depotGradeLabel(depot.grade)}</span>` : ""
      const routeNames = this.depotRouteNames(depot)
      const routeNote = routeNames.length > 0
        ? `<br><span style="opacity:0.8">${this.t("depot.serving_routes", { routes: routeNames.join(this.t("list_sep")) })}</span>`
        : ""

      marker.bindPopup(
        `<strong>${depot.name}</strong>${gradeNote}${routeNote}<br><span style="opacity:0.8">${this.t("depot.vehicle_base")}</span>`
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

  renderDepotTrackLinks(depot, color) {
    const L = window.L
    const group = this.metroDepotGroup
    if (!group || !this.map) return

    const links = depot.track_links || []

    links.forEach((link) => {
      if (!link?.route_id || !this.isRouteLayerVisible(link.route_id)) return
      if (!Array.isArray(link.coordinates) || link.coordinates.length < 2) return
      if (this.depotSpurInRouteGeojson(depot.id, link.route_id)) return

      const latlngs = link.coordinates.map(([ lon, lat ]) => L.latLng(lat, lon))
      const line = L.polyline(latlngs, {
        color: color || "#64748B",
        weight: 4,
        opacity: 0.85,
        lineCap: "round",
        lineJoin: "round",
        className: "depot-track-link"
      })

      group.addLayer(line)
    })
  }

  depotSpurInRouteGeojson(depotId, routeId) {
    const route = this.findRoute(routeId)
    const file = route?.file || route?.url
    const data = file ? this.geoJSONDataByUrl[file] : null
    if (!data?.features) return false

    return data.features.some((feature) => (
      feature.properties?.feature_type === "depot_spur" &&
      feature.properties?.depot_id === depotId
    ))
  }

  depotDisplayColor(depot) {
    const trackRouteId = depot.track_links?.[0]?.route_id
    if (trackRouteId && this.isRouteLayerVisible(trackRouteId)) {
      const color = this.routeDisplayColor(this.findRoute(trackRouteId))
      if (color) return color
    }

    for (const routeId of depot.routes || []) {
      if (!this.isRouteLayerVisible(routeId)) continue
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
    if (depot.id?.startsWith("tra_")) return []

    return (depot.routes || [])
      .map((routeId) => this.routeDisplayName(this.findRoute(routeId)))
      .filter(Boolean)
  }

  depotGradeLabel(grade) {
    const translated = this.t(`depot.grades.${grade}`)
    if (translated && translated !== `depot.grades.${grade}`) return translated

    return this.t("depot.suffix", { grade })
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

  isInStationTransferRef(ref, routeId = null) {
    return this.isInSystemInStationTransferRef(ref, routeId) || this.isCrossSystemTransferRef(ref)
  }

  isInSystemInStationTransferRef(ref, routeId = null) {
    const parts = this.transferStationRefs(ref)
    if (parts.length <= 1) return false
    if (this.isAirportMrtExpressStop(ref)) return false
    if (this.isKaohsiungCrossRouteTransferRef(ref)) return false
    if (this.isDeclaredOutOfStationTransferRef(ref)) return false

    return this.transferSystemIds(ref).length <= 1
  }

  // Combined refs like BR01;G1 are walk transfers between separate platforms, not ovals.
  isDeclaredOutOfStationTransferRef(ref) {
    const parts = this.transferStationRefs(ref)
    if (parts.length <= 1) return false

    return (this.outOfStationTransfers || []).some((transfer) => {
      const endpointRefs = new Set()

      ;(transfer.endpoints || []).forEach((endpoint) => {
        this.transferStationRefs(endpoint.ref).forEach((stationRef) => endpointRefs.add(stationRef))
      })

      return parts.every((part) => endpointRefs.has(part))
    })
  }

  isCrossSystemTransferRef(ref) {
    const parts = this.transferStationRefs(ref)
    if (parts.length <= 1) return false
    if (this.isAirportMrtExpressStop(ref)) return false
    if (this.isDeclaredOutOfStationTransferRef(ref)) return false

    return this.transferSystemIds(ref).length > 1 || this.isKaohsiungCrossRouteTransferRef(ref)
  }

  // Circular LRT and Kaohsiung MRT share a system id but use separate platforms (e.g. C14/O1 哈瑪星).
  isKaohsiungCrossRouteTransferRef(ref) {
    const parts = this.transferStationRefs(ref)
    if (parts.length !== 2) return false

    const routeIds = new Set(
      parts.map((part) => this.routeIdForStationRefPart(part, parts)).filter(Boolean)
    )

    if (routeIds.size <= 1) return false

    return Array.from(routeIds).every((routeId) => this.manifestSystemForRoute(routeId) === "kaohsiung_metro")
  }

  manifestRouteIdsForStationRefPart(part) {
    if (!part) return []

    const routeIds = []

    for (const routes of Object.values(this.routesManifest)) {
      if (!Array.isArray(routes)) continue

      for (const route of routes) {
        if (!this.stationRefMatchesRoute(part, route.ref, route.id)) continue

        routeIds.push(route.id)
      }
    }

    return routeIds
  }

  isZhongheStationRefPart(part) {
    if (!part) return false

    return /^O(?:0[1-9]|10|11|1[2-9]|2[0-1]|5[0-4])$/i.test(part)
  }

  routeIdForStationRefPartInTransfer(part, parts) {
    const sibling = parts.find((candidate) => candidate !== part)
    if (!sibling) return null

    const siblingRouteIds = this.manifestRouteIdsForStationRefPart(sibling)
    const partRouteIds = this.manifestRouteIdsForStationRefPart(part)
    const siblingSystems = new Set(
      siblingRouteIds.map((routeId) => this.manifestSystemForRoute(routeId)).filter(Boolean)
    )

    if (this.isZhongheStationRefPart(sibling) && siblingRouteIds.includes("zhonghe_xinlu")) {
      if (this.isZhongheStationRefPart(part)) return "zhonghe_xinlu"

      const partnerRouteId = partRouteIds.find(
        (routeId) => routeId !== "zhonghe_xinlu" && this.manifestSystemForRoute(routeId) === "taipei_metro"
      )
      if (partnerRouteId) return partnerRouteId
    }

    if (siblingSystems.has("taipei_metro") && this.isZhongheStationRefPart(part)) {
      return "zhonghe_xinlu"
    }

    if (/^O1$/i.test(part) && siblingRouteIds.includes("circular_lrt")) return "orange_line"
    if (/^C\d/i.test(part) && siblingRouteIds.includes("orange_line")) return "circular_lrt"

    if (/^G[1-6]$/i.test(part) && partRouteIds.includes("maokong_gondola") &&
        (siblingRouteIds.includes("wenhu_line") || /^BR\d/i.test(sibling))) {
      return "maokong_gondola"
    }
    if (/^BR\d/i.test(part) && partRouteIds.includes("wenhu_line") &&
        (siblingRouteIds.includes("maokong_gondola") || /^G[1-6]$/i.test(sibling))) {
      return "wenhu_line"
    }

    const kaohsiungSiblingRouteIds = siblingRouteIds.filter(
      (routeId) => this.manifestSystemForRoute(routeId) === "kaohsiung_metro"
    )
    const siblingIsTaipeiZhongheO = this.isZhongheStationRefPart(sibling) && siblingRouteIds.includes("zhonghe_xinlu")
    if (!siblingIsTaipeiZhongheO) {
      if (/^R\d/i.test(part) && kaohsiungSiblingRouteIds.includes("orange_line") && partRouteIds.includes("red_line")) {
        return "red_line"
      }
      if (/^O\d/i.test(part) && !this.isZhongheStationRefPart(part) &&
          kaohsiungSiblingRouteIds.includes("red_line") && partRouteIds.includes("orange_line")) {
        return "orange_line"
      }
    }

    return null
  }

  routeIdForStationRefPart(part, contextParts = null) {
    if (!part) return null

    const transferParts = contextParts || (part.includes(";") ? this.transferStationRefs(part) : [ part ])
    if (transferParts.length === 2) {
      const contextualRouteId = this.routeIdForStationRefPartInTransfer(part, transferParts)
      if (contextualRouteId) return contextualRouteId
    }

    for (const routes of Object.values(this.routesManifest)) {
      if (!Array.isArray(routes)) continue

      for (const route of routes) {
        if (!this.stationRefMatchesRoute(part, route.ref, route.id)) continue

        return route.id
      }
    }

    return null
  }

  transferSystemIds(ref) {
    const parts = this.transferStationRefs(ref)
    const systemIds = new Set()

    parts.forEach((part) => {
      const routeId = this.routeIdForStationRefPart(part, parts)
      const systemId = routeId ? this.manifestSystemForRoute(routeId) : this.systemIdForStationRefPart(part)
      if (systemId) systemIds.add(systemId)
    })

    return Array.from(systemIds)
  }

  systemIdForStationRefPart(part) {
    if (!part) return null
    if (/^\d{3,4}(-[A-Z]+)?$/.test(part)) return "tra"
    if (/^\d{2}$/.test(part)) return "hsr"

    for (const routes of Object.values(this.routesManifest)) {
      if (!Array.isArray(routes)) continue

      for (const route of routes) {
        if (!this.stationRefMatchesRoute(part, route.ref, route.id)) continue

        return this.manifestSystemForRoute(route.id)
      }
    }

    return "other"
  }

  inStationTransferMarkerKey(ref, routeId = null) {
    const parts = this.transferStationRefs(ref)
    const traRef = parts.find((part) => /^\d{3,4}(-[A-Z]+)?$/.test(part))
    if (traRef) {
      const numericRef = traRef.match(/^(\d+)/)?.[1]
      if (numericRef) return `hub:tra:${numericRef}`
    }

    if (parts.length > 1) return parts.slice().sort().join(";")

    if (routeId && this.isTraRoute(routeId)) {
      const numericRef = this.traNumericStationRef(ref)
      if (numericRef) return `hub:tra:${numericRef}`
    }

    return ref || ""
  }

  shouldShowInStationTransferMarker(ref, routeId) {
    if (!this.isInSystemInStationTransferRef(ref, routeId)) return false

    // Only draw the oval when at least two participating lines are visible.
    // Otherwise wenhu-only views would show ovals for R/BL/G partners that are off.
    const visibleParts = this.transferStationRefs(ref).filter((part) => {
      return this.manifestRouteIdsForStationRefPart(part).some((id) => this.layerVisible[id])
    })

    return visibleParts.length >= 2
  }

  shouldHideStationForTransfer(ref, routeId = null) {
    // Only same-system in-station ovals replace the underlying station dots.
    // Cross-system hubs use class 2–4 connection lines and keep station markers.
    return this.shouldShowInStationTransferMarker(ref, routeId)
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
          if (!this.shouldShowInStationTransferMarker(ref, route.id)) return

          const key = this.inStationTransferMarkerKey(ref, route.id)
          if (!transfersByKey.has(key)) transfersByKey.set(key, feature)
        })
      })
    })

    transfersByKey.forEach((feature) => {
      const ref = feature.properties?.ref
      const name = this.featureDisplayName(feature)
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

      marker.bindPopup(`<strong>${label}</strong><br><span style="opacity:0.8">${this.t("transfer.in_station")}</span>`)
      group.addLayer(marker)
    })

    if (group.getLayers().length > 0) {
      if (!this.map.hasLayer(group)) group.addTo(this.map)
      group.bringToFront()
    } else if (this.map.hasLayer(group)) {
      this.map.removeLayer(group)
    }
  }

  updateCrossSystemInStationTransfers() {
    const L = window.L
    const group = this.crossSystemInStationTransferGroup

    if (!group || !this.map) return

    group.clearLayers()

    const hubsByKey = new Map()

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
          if (!this.isCrossSystemTransferRef(ref)) return

          const key = this.inStationTransferMarkerKey(ref, route.id)
          if (!hubsByKey.has(key)) hubsByKey.set(key, feature)
        })
      })
    })

    // Cross-system hubs are class 2 (solid links), never class 1 ovals.
    // Skip pairs already declared in out_of_station_transfers.json.
    hubsByKey.forEach((feature, hubKey) => {
      const endpoints = this.crossSystemHubEndpoints(hubKey)
      if (endpoints.length < 2) return

      const name = this.featureDisplayName(feature)
      const label = name || this.t("transfer.cross_system")
      const note = this.transferNoteForKind("passage")

      for (let index = 0; index < endpoints.length - 1; index += 1) {
        const left = endpoints[index]
        const right = endpoints[index + 1]
        if (this.outOfStationTransferCoversRoutePair(left.routeId, right.routeId)) continue

        const layers = this.transferConnectionLayers([ left.latlng, right.latlng ], "passage")
        layers.forEach((layer) => {
          layer.bindPopup(`<strong>${label}</strong><br><span style="opacity:0.8">${note}</span>`)
          group.addLayer(layer)
        })
      }
    })

    if (group.getLayers().length > 0) {
      if (!this.map.hasLayer(group)) group.addTo(this.map)
      group.bringToFront()
    } else if (this.map.hasLayer(group)) {
      this.map.removeLayer(group)
    }
  }

  outOfStationTransferCoversRoutePair(routeIdA, routeIdB) {
    if (!routeIdA || !routeIdB) return false

    return (this.outOfStationTransfers || []).some((transfer) => {
      const routes = transfer.routes || []
      return routes.includes(routeIdA) && routes.includes(routeIdB)
    })
  }

  crossSystemHubEndpoints(hubKey) {
    const L = window.L
    const endpoints = []
    const systemsSeen = new Set()
    const routesSeen = new Set()

    this.visibleRouteLayerIds().forEach((layerId) => {
      this.routesToLoad(layerId).forEach((route) => {
        if (!this.layerVisible[route.id]) return

        const systemId = this.manifestSystemForRoute(route.id)
        if (!systemId) return

        const file = route.file || route.url
        const data = file ? this.geoJSONDataByUrl[file] : null
        if (!data) return

        const displayData = this.displayGeoJSON(data, route)

        for (const feature of displayData.features || []) {
          if (feature.properties?.feature_type !== "station") continue

          const ref = feature.properties?.ref
          if (!this.isCrossSystemTransferRef(ref)) continue
          if (this.inStationTransferMarkerKey(ref, route.id) !== hubKey) continue

          const crossRoute = this.isKaohsiungCrossRouteTransferRef(ref)
          const dedupeKey = crossRoute ? route.id : systemId
          const seen = crossRoute ? routesSeen : systemsSeen
          if (seen.has(dedupeKey)) continue

          const coordinates = feature.geometry?.coordinates
          if (!coordinates) continue

          const latlng = L.latLng(coordinates[1], coordinates[0])
          const stationRefs = this.transferStationRefs(ref)
          const routePart = stationRefs.find((part) => this.stationRefMatchesRoute(part, route.ref, route.id)) || stationRefs[0]
          const linePrefix = this.linePrefixForStationRef(routePart) || route.ref
          const position = this.snapToRouteTracks(latlng, route.id) ||
            this.snapToTracks(latlng, linePrefix) ||
            latlng

          endpoints.push({
            systemId,
            routeId: route.id,
            latlng: position,
            name: feature.properties?.name
          })
          seen.add(dedupeKey)
          break
        }
      })
    })

    return endpoints
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

    ;[ this.outOfStationTransferGroup, this.crossSystemInStationTransferGroup, this.inStationTransferGroup, this.metroDepotGroup ].forEach((group) => {
      if (group && this.map.hasLayer(group) && group.getLayers().length > 0) {
        combined.addLayer(group)
      }
    })

    if (combined.getLayers().length === 0) return

    try {
      const bounds = combined.getBounds()
      if (bounds.isValid()) {
        this.map.fitBounds(bounds.pad(0.1), { maxZoom: 11 })
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
      if (this.isTraRoute(layerId)) {
        void this.refreshTraSharedStationLayers()
      }
    }

    const systemId = this.manifestSystemForRoute(layerId)
    if (systemId && METRO_SYSTEM_IDS.includes(systemId)) {
      this.syncMetroSystemCheckbox(systemId)
    } else if (systemId) {
      this.syncManifestSystemCheckbox(systemId)
      if (systemId === "tra") this.syncAllTraCheckbox()
    }

    this.syncAllMetroCheckbox()
    this.syncAllTraCheckbox()
    this.syncAllTransitCheckbox()
    this.updateOutOfStationTransfers()
  }

  async showLayer(layerId, { checkbox = null, fitBounds = true, manageControl = true } = {}) {
    const control = checkbox || this.checkboxForLayer(layerId)
    if (!this.mapReady || !this.map) return

    this.ensureLayerGroup(layerId)

    const group = this.layerGroups[layerId]
    if (this.layerVisible[layerId] && group?.getLayers().length > 0) {
      if (control) control.checked = true
      if (!this.map.hasLayer(group)) group.addTo(this.map)
      if (fitBounds) this.fitLayerBounds(layerId)
      this.updateOutOfStationTransfers()
      this.applyRouteEmphasis()
      this.refreshStationLabels()
      if (this.simulationAt) this.scheduleVehicleRefresh()
      return
    }

    const generation = this.bumpLayerGeneration(layerId)
    this.layerVisible[layerId] = true
    if (control) {
      control.checked = true
      if (manageControl) control.disabled = true
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
      this.applyRouteEmphasis()
      this.refreshStationLabels()
      if (this.simulationAt) this.scheduleVehicleRefresh()
    } catch (error) {
      console.error("Failed to load layer", layerId, error)
      this.hideLayer(layerId)
      if (control) this.resetLayerCheckbox(control, layerId)
    } finally {
      if (manageControl && control && this.mapReady) control.disabled = false
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
    if (this.simulationAt) this.scheduleVehicleRefresh()

    this.clearStationCoordinatesForRoutes(this.routesToLoad(layerId))

    this.routesToLoad(layerId).forEach((route) => {
      if (route?.id) {
        delete this.routeTracksByRouteId[route.id]
        delete this.vehicleTracksByRouteId[route.id]
        delete this.routeChainage[route.id]
      }
    })

    this.clearStationLabelsForLayer(layerId)
    this.updateOutOfStationTransfers()
    this.applyRouteEmphasis()
    this.refreshStationLabels()
  }

  async loadLayer(layerId, generation, { skipTraRefresh = false } = {}) {
    const group = this.layerGroups[layerId]
    if (!group) return

    this.refreshTraSharedStationOwners()

    const metroRoutes = this.routesToLoad(layerId)
    const routes = metroRoutes.length > 0 ? metroRoutes : (this.routesManifest[layerId] || [])
    if (routes.length === 0) return

    const results = await Promise.allSettled(
      routes.map((route) => this.addRouteToGroup(route, layerId, generation))
    )

    if (!this.isLayerGenerationCurrent(layerId, generation)) return

    const failures = results.filter((result) => result.status === "rejected")
    if (failures.length > 0) {
      console.warn(`Layer ${layerId}: ${failures.length}/${results.length} routes failed to load`, failures)
    }

    if (group.getLayers().length === 0 && failures.length > 0) {
      throw failures[0].reason
    }

    if (!skipTraRefresh && this.isTraRoute(layerId)) {
      await this.refreshTraSharedStationLayers(layerId)
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
    this.clearTerminalRolesFromGeoJSON(data)

    const displayData = this.displayGeoJSON(data, route)
    const renderData = this.cloneGeoJSONForRender(this.geoJSONForMapRender(displayData, route))
    this.clearTerminalRolesFromGeoJSON(renderData)

    this.cacheRouteTracks(route.id, displayData)
    this.indexStationCoordinates(route.id, renderData)

    const geoLayer = L.geoJSON(renderData, {
      style: (feature) => this.styleForFeature(feature, color, route),
      pointToLayer: (feature, latlng) => {
        if (this.shouldHideStationForTransfer(feature.properties?.ref, route.id)) {
          return this.hiddenStationMarker(latlng)
        }

        return this.stationMarker(feature, latlng, color, routeRef, route.id)
      },
      onEachFeature: (feature, layer) => {
        if (route.id === "airport_mrt" || route.id === "airport_mrt_express") {
          const lineStyle = this.styleForFeature(feature, color, route)
          if (lineStyle.color && typeof layer.setStyle === "function") layer.setStyle(lineStyle)
        }

        this.registerStationLabel(feature, layer, route)
        this.bindFeaturePopup(feature, layer, route.id)
      }
    })

    if (!this.isLayerGenerationCurrent(layerId, generation) || !this.layerVisible[layerId]) return

    group.addLayer(geoLayer)

    if (layerId === "airport_mrt") this.bringAirportMrtCommuterLinesToFront(group)
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

  stationRefSortKey(ref) {
    const value = (ref || "").split(";")[0]
    const prefix = value.match(/^[A-Z]+/)?.[0] || ""
    const numeric = value.match(/\d+/)?.[0] || "0"
    const suffix = value.slice(prefix.length + numeric.length)
    const suffixRank = /^\d+[a-z]$/i.test(value) ? 0 : suffix ? 2 : 1

    return [ prefix, parseInt(numeric, 10), suffixRank, suffix ]
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
    if (feature?.properties?.shared_junction) return false

    const role = feature?.properties?.station_role
    return role === "origin" || role === "destination"
  }

  terminalStationLabel(feature) {
    const role = feature?.properties?.station_role
    if (role === "origin") return this.t("terminal.origin")
    if (role === "destination") return this.t("terminal.destination")
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

    if (this.isTraRoute(route?.id)) {
      features = this.filterTraSharedStationFeatures(features, route)
    }

    return { ...data, features }
  }

  refreshTraSharedStationOwners() {
    this.traStationOwnerByRef = this.buildTraStationOwnerByRef()
  }

  buildTraStationOwnerByRef() {
    const owners = new Map()

    ;(this.routesManifest.tra || []).forEach((route) => {
      if (!this.isRouteLayerVisible(route.id)) return

      const file = route.file || route.url
      const data = file ? this.geoJSONDataByUrl[file] : null
      if (!data) return

      this.stationRefsFromGeoJSON(data).forEach((ref) => {
        const numericRef = this.traNumericStationRef(ref)
        if (!numericRef) return

        const current = owners.get(numericRef)
        const routePriority = this.traBranchJunctionPriority(route.id, numericRef)
        const currentPriority = current
          ? this.traBranchJunctionPriority(current, numericRef)
          : Number.POSITIVE_INFINITY

        if (!current || routePriority < currentPriority) {
          owners.set(numericRef, route.id)
        }
      })
    })

    return owners
  }

  stationRefsFromGeoJSON(data) {
    return (data.features || []).flatMap((feature) => {
      if (feature.properties?.feature_type !== "station") return []

      const ref = feature.properties?.ref
      return ref ? [ ref ] : []
    })
  }

  traRouteStationPriority(routeId) {
    if (!TRA_BRANCH_ROUTE_IDS.has(routeId)) return 0

    return TRA_BRANCH_ROUTE_PRIORITY[routeId] ?? 1
  }

  traBranchJunctionRefs(routeId) {
    return TRA_BRANCH_JUNCTION_REFS[routeId] || []
  }

  traMainLineJunctionRefs(routeId) {
    return TRA_MAIN_LINE_JUNCTION_REFS[routeId] || []
  }

  traLineOriginRefs(routeId) {
    return TRA_LINE_ORIGIN_REFS[routeId] || []
  }

  traLineFinishRefs(routeId) {
    return TRA_LINE_FINISH_REFS[routeId] || []
  }

  traBranchJunctionPriority(routeId, ref) {
    if (this.traBranchJunctionRefs(routeId).includes(ref)) return -1
    if (this.traLineOriginRefs(routeId).includes(ref)) return -1
    if (this.traLineFinishRefs(routeId).includes(ref)) return -1
    if (this.traMainLineJunctionRefs(routeId).includes(ref)) return 0

    return this.traRouteStationPriority(routeId)
  }

  traNumericStationRef(ref) {
    if (!ref) return null

    const primary = ref.toString().split(";")[0].trim()
    const junction = primary.match(/^(\d+)-[A-Z]+$/)
    if (junction) return junction[1]

    return /^\d+$/.test(primary) ? primary : null
  }

  filterTraSharedStationFeatures(features, route) {
    const owners = this.traStationOwnerByRef || new Map()

    return features.filter((feature) => {
      if (feature.properties?.feature_type !== "station") return true

      const ref = this.traNumericStationRef(feature.properties?.ref)
      if (!ref) return true

      if (feature.properties?.shared_junction) return true

      const owner = owners.get(ref)
      return !owner || owner === route.id
    })
  }

  async refreshTraSharedStationLayers(justLoadedId = null) {
    this.refreshTraSharedStationOwners()

    const routeIds = (this.routesManifest.tra || [])
      .map((route) => route.id)
      .filter((routeId) => {
        return routeId !== justLoadedId &&
          this.layerVisible[routeId] &&
          this.layerGroups[routeId]?.getLayers().length > 0
      })

    await Promise.all(routeIds.map((routeId) => this.reloadTraLayer(routeId)))
  }

  async reloadTraLayer(layerId) {
    const generation = this.bumpLayerGeneration(layerId)
    const group = this.layerGroups[layerId]
    if (!group) return

    group.clearLayers()
    await this.loadLayer(layerId, generation, { skipTraRefresh: true })
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

    const labels = segments.map((segment) => (
      segment === "lushan" ? this.t("sections.lushan") : this.t("sections.lanhai")
    ))

    return this.t("lines.danhai", { segments: labels.join(this.t("segment_sep")) })
  }

  skytrainLineLabel(feature) {
    const segment = feature.properties?.segment
    if (segment === "north") return this.t("lines.skytrain_north")
    if (segment === "south") return this.t("lines.skytrain_south")

    return feature.properties?.line
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
    if (!ref) return false

    return this.transferStationRefs(ref).some((part) => AIRPORT_MRT_EXPRESS_STOP_REFS.has(part))
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
    const emphasisId = this.emphasizedRouteId()
    const dimmed = Boolean(emphasisId && route?.id && route.id !== emphasisId)
    const haloBoost = this.routeStrokeBoost()
    const dimFactor = dimmed ? 0.28 : 1

    if (isExpress) {
      return {
        pane: this.expressRoutePane,
        className: `airport-mrt-express-line${haloBoost ? " route-line--halo" : ""}${dimmed ? " route-line--dimmed" : ""}`,
        color: EXPRESS_LINE_COLOR,
        weight: 6 + haloBoost,
        opacity: 1 * dimFactor,
        lineCap: "round",
        lineJoin: "round"
      }
    }

    if (route?.id === "airport_mrt") {
      return {
        pane: this.commuterRoutePane,
        className: `airport-mrt-commuter-line${haloBoost ? " route-line--halo" : ""}${dimmed ? " route-line--dimmed" : ""}`,
        color: AIRPORT_MRT_COMMUTER_COLOR,
        weight: 6 + haloBoost,
        opacity: 0.95 * dimFactor,
        lineCap: "round",
        lineJoin: "round"
      }
    }

    if (route?.id === "danhai_lrt") {
      return {
        className: `${haloBoost ? "route-line--halo" : ""}${dimmed ? " route-line--dimmed" : ""}`.trim(),
        color: DANHAI_LRT_COLOR,
        weight: 6 + haloBoost,
        opacity: 0.95 * dimFactor,
        lineCap: "round",
        lineJoin: "round"
      }
    }

    if (feature.properties?.feature_type === "depot_spur") {
      return {
        className: `depot-spur-line${haloBoost ? " route-line--halo" : ""}${dimmed ? " route-line--dimmed" : ""}`,
        color: feature.properties?.color || this.routeDisplayColor(route) || color,
        weight: 4 + Math.min(haloBoost, 1),
        opacity: 0.85 * dimFactor,
        lineCap: "round",
        lineJoin: "round"
      }
    }

    return {
      className: `${haloBoost ? "route-line--halo" : ""}${dimmed ? " route-line--dimmed" : ""}`.trim(),
      color: feature.properties?.color || this.routeDisplayColor(route) || color,
      weight: 5 + haloBoost,
      opacity: 0.9 * dimFactor,
      lineCap: "round",
      lineJoin: "round"
    }
  }

  emphasizedRouteId() {
    if (this.selectedRouteId) return this.selectedRouteId

    const visible = this.visibleRouteLayerIds()
    return visible.length === 1 ? visible[0] : null
  }

  routeStrokeBoost() {
    const dark = document.documentElement.classList.contains("dark")
    if (this.basemapStyle === "sat") return 2
    if (dark) return 1
    return 0
  }

  applyRouteEmphasis() {
    if (!this.map || !this.layerGroups) return

    this.visibleRouteLayerIds().forEach((layerId) => {
      const route = this.findRoute(layerId)
      const group = this.layerGroups[layerId]
      if (!group || !route) return

      const color = this.routeDisplayColor(route) || LAYER_COLORS[layerId] || "#666666"

      group.eachLayer((geoLayer) => {
        if (typeof geoLayer.eachLayer !== "function") return

        geoLayer.eachLayer((layer) => {
          if (!layer.feature || typeof layer.setStyle !== "function") return
          if (!this.isRouteLineFeature(layer.feature) && layer.feature.properties?.feature_type !== "depot_spur") return

          layer.setStyle(this.styleForFeature(layer.feature, color, route))
        })
      })
    })
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
    this.routeTracksByRouteId[routeId] = this.extractRouteTracks(data, { includeDepot: true })
    // Vehicle motion must follow the passenger main line, never depot spurs.
    this.vehicleTracksByRouteId[routeId] = this.extractRouteTracks(data, { includeDepot: false })
  }

  extractRouteTracks(data, { includeDepot = true } = {}) {
    const lines = []

    ;(data.features || []).forEach((feature) => {
      const featureType = feature.properties?.feature_type
      const allowed =
        featureType === "route" ||
        featureType === "express_route" ||
        (includeDepot && featureType === "depot_spur")
      if (!allowed) return

      const geometry = feature.geometry
      if (geometry?.type === "LineString") {
        lines.push(geometry.coordinates)
      } else if (geometry?.type === "MultiLineString") {
        geometry.coordinates.forEach((coordinates) => lines.push(coordinates))
      }
    })

    return lines
  }

  vehicleTracksFor(routeId) {
    return this.vehicleTracksByRouteId[routeId] || this.routeTracksByRouteId[routeId] || []
  }

  routeUsesParallelTracks(route) {
    if (!PARALLEL_TRACK_ROUTE_IDS.has(route?.id)) return false

    // Zoomed out: keep a single corridor so geographic offsets do not fan into scallops.
    const zoom = this.map?.getZoom() ?? 12
    return zoom >= PARALLEL_TRACK_MIN_ZOOM
  }

  scheduleParallelTracksRefresh() {
    if (!this.map) return

    const parallelActive = (this.map.getZoom() ?? 12) >= PARALLEL_TRACK_MIN_ZOOM
    if (this.parallelTracksActive === parallelActive) return

    this.parallelTracksActive = parallelActive

    if (this.parallelTracksRefreshTimer) clearTimeout(this.parallelTracksRefreshTimer)

    this.parallelTracksRefreshTimer = setTimeout(() => {
      this.parallelTracksRefreshTimer = null
      this.refreshVisibleParallelLayers()
    }, 120)
  }

  async refreshVisibleParallelLayers() {
    if (!this.mapReady || !this.map) return

    const layerIds = this.visibleRouteLayerIds().filter((layerId) => {
      return this.routesToLoad(layerId).some((route) => PARALLEL_TRACK_ROUTE_IDS.has(route?.id))
    })
    if (layerIds.length === 0) return

    await this.mapPool(layerIds, LAYER_LOAD_CONCURRENCY, async (layerId) => {
      const generation = this.bumpLayerGeneration(layerId)
      const group = this.layerGroups[layerId]
      if (!group) return

      this.clearStationLabelsForLayer(layerId)
      group.clearLayers()

      try {
        await this.loadLayer(layerId, generation)
      } catch (error) {
        console.warn("Failed to refresh parallel tracks for", layerId, error)
        return
      }

      if (!this.isLayerGenerationCurrent(layerId, generation) || !this.layerVisible[layerId]) return

      if (group.getLayers().length > 0) {
        if (!this.map.hasLayer(group)) group.addTo(this.map)
        if (layerId === "airport_mrt") this.bringAirportMrtCommuterLinesToFront(group)
      }
    })

    this.reindexVisibleStationCoordinates()
    this.updateOutOfStationTransfers()
    this.updateMetroDepots()
    this.applyRouteEmphasis()
    this.refreshStationLabels()
  }

  parallelHalfOffsetMeters(_data) {
    return PARALLEL_TRACK_HALF_OFFSET_M
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

  routeLineForSegment(data, segment) {
    for (const feature of data.features || []) {
      if (feature.properties?.feature_type !== "route") continue
      if (feature.properties?.segment !== segment) continue

      const coordinates = feature.geometry?.coordinates
      if (feature.geometry?.type === "LineString" && coordinates?.length >= 2) return coordinates
    }

    return []
  }

  danhaiRouteLineForSegment(data, segment) {
    return this.routeLineForSegment(data, segment)
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

    if (route.id === "taoyuan_airport_skytrain") {
      const segment = feature.properties?.segment
      if (segment === "north") return -halfOffset
      if (segment === "south") return halfOffset
    }

    return null
  }

  bearingLineForFeature(route, feature, data, referenceLine) {
    if (route.id === "airport_mrt" || route.id === "airport_mrt_express") {
      return referenceLine.length >= 2 ? referenceLine : this.coordinatesFromFeature(feature)
    }

    if (feature.properties?.segment) {
      const segmentLine = this.routeLineForSegment(data, feature.properties.segment)
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
        const projected = this.projectLatLngOnSegment(latlng, start, end)
        const distance = latlng.distanceTo(projected)

        if (distance < bestDistance) {
          bestDistance = distance
          bestLatLng = projected
        }
      }
    })

    return bestLatLng
  }

  projectLatLngOnSegment(point, start, end) {
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
          color: TRANSFER_LINE_COLOR_PASSAGE,
          weight: TRANSFER_LINE_WEIGHT_PASSAGE,
          opacity: 0.95,
          lineCap: "round",
          lineJoin: "round",
          className: "out-of-station-transfer-line out-of-station-transfer-line--passage"
        })
      ]
    }

    if (kind === "walk_transfer") {
      return [
        L.polyline(path, {
          pane: this.outOfStationTransferPane,
          color: TRANSFER_LINE_COLOR_WALK,
          weight: TRANSFER_LINE_WEIGHT_WALK,
          opacity: 0.9,
          lineCap: "round",
          lineJoin: "round",
          className: "out-of-station-transfer-line out-of-station-transfer-line--walk-transfer",
          dashArray: "2 6"
        })
      ]
    }

    // fare_discount — single dashed connector (no double-track style).
    return [
      L.polyline(path, {
        pane: this.outOfStationTransferPane,
        color: "#ffffff",
        weight: TRANSFER_LINE_WEIGHT_FARE_DISCOUNT + 3,
        opacity: 0.85,
        lineCap: "round",
        lineJoin: "round",
        className: "out-of-station-transfer-line out-of-station-transfer-line--fare-discount-casing",
        dashArray: "10 8"
      }),
      L.polyline(path, {
        pane: this.outOfStationTransferPane,
        color: TRANSFER_LINE_COLOR_FARE_DISCOUNT,
        weight: TRANSFER_LINE_WEIGHT_FARE_DISCOUNT,
        opacity: 1,
        lineCap: "round",
        lineJoin: "round",
        className: "out-of-station-transfer-line out-of-station-transfer-line--fare-discount",
        dashArray: "10 8"
      })
    ]
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
      const key = this.stationKey(routeId, stationRef)
      if (!this.outOfStationEndpointKeys?.has(key)) return false

      // HSR uses numeric refs; show regular stations unless a linked metro line is also on.
      if (routeId === "taiwan_hsr") {
        return this.hasVisibleLinkedTransferRoute(routeId, stationRef)
      }

      return true
    })
  }

  hasVisibleLinkedTransferRoute(routeId, stationRef) {
    return (this.outOfStationTransfers || []).some((transfer) => {
      if (!transfer.routes?.includes(routeId)) return false

      const matchesEndpoint = transfer.endpoints?.some((endpoint) => {
        if (endpoint.route_id !== routeId) return false

        return this.transferStationRefs(endpoint.ref).includes(stationRef)
      })

      if (!matchesEndpoint) return false

      return transfer.routes.some((linkedRouteId) => {
        return linkedRouteId !== routeId && this.layerVisible[linkedRouteId]
      })
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

  registerStationLabel(feature, layer, route) {
    const featureType = feature.properties?.feature_type
    if (featureType !== "station" && featureType !== "angle_station") return
    if (featureType === "station" && feature.properties?.passenger_service === false) return

    const name = this.featureDisplayName(feature)
    if (!name) return

    const latlng = layer.getLatLng?.()
    if (!latlng) return

    const ref = feature.properties?.ref || ""
    const routeId = route?.id
    const key = `${routeId}:${ref}:${featureType}`
    const priority = this.stationLabelPriority(feature, routeId, ref)

    this.stationLabelEntries = (this.stationLabelEntries || []).filter((entry) => entry.key !== key)
    this.stationLabelEntries.push({
      key,
      routeId,
      layerId: routeId,
      name,
      latlng,
      priority
    })
  }

  stationLabelPriority(feature, routeId, stationRef) {
    if (this.isAirportMrtExpressTransferStation(routeId, stationRef)) return 3
    if (this.isOutOfStationEndpoint(routeId, stationRef)) return 3
    if (this.isCrossSystemTransferRef(stationRef)) return 3
    if (this.shouldShowInStationTransferMarker(stationRef, routeId)) return 3
    if ((stationRef || "").includes(";")) return 3
    if (this.isTerminalStation(feature)) return 2
    return 1
  }

  clearStationLabelsForLayer(layerId) {
    const routeIds = new Set(this.routesToLoad(layerId).map((route) => route?.id).filter(Boolean))
    routeIds.add(layerId)
    this.stationLabelEntries = (this.stationLabelEntries || []).filter((entry) => !routeIds.has(entry.routeId) && !routeIds.has(entry.layerId))
  }

  routeLabelFocusId() {
    if (this.initialRouteIdValue) return this.initialRouteIdValue
    if (this.selectedRouteId && this.visibleRouteLayerIds().length === 1) return this.selectedRouteId
    return null
  }

  scheduleStationLabelRefresh() {
    if (this.stationLabelRefreshTimer) clearTimeout(this.stationLabelRefreshTimer)
    this.stationLabelRefreshTimer = setTimeout(() => {
      this.stationLabelRefreshTimer = null
      this.refreshStationLabels()
    }, 120)
  }

  refreshStationLabels() {
    if (!this.map || !this.stationLabelGroup || !window.L) return

    const L = window.L
    this.stationLabelGroup.clearLayers()

    const focusRouteId = this.routeLabelFocusId()
    const bounds = this.map.getBounds().pad(0.08)
    let candidates

    if (focusRouteId) {
      // Route detail: show every station name to the right of its marker.
      const focusRouteIds = new Set(this.routesToLoad(focusRouteId).map((route) => route?.id).filter(Boolean))
      focusRouteIds.add(focusRouteId)

      candidates = (this.stationLabelEntries || [])
        .filter((entry) => focusRouteIds.has(entry.routeId) && bounds.contains(entry.latlng))
        .sort((a, b) => b.priority - a.priority || a.name.localeCompare(b.name, "zh-Hant"))
    } else {
      const zoom = this.map.getZoom() ?? 0
      if (zoom < STATION_LABEL_PRIORITY_ZOOM) return

      const minPriority = zoom >= STATION_LABEL_MIN_ZOOM ? 1 : 2
      candidates = (this.stationLabelEntries || [])
        .filter((entry) => entry.priority >= minPriority && bounds.contains(entry.latlng))
        .sort((a, b) => b.priority - a.priority || a.name.length - b.name.length)
    }

    const placed = []
    const skipCollision = Boolean(focusRouteId)

    candidates.forEach((entry) => {
      const point = this.map.latLngToContainerPoint(entry.latlng)
      const width = Math.min(12 + entry.name.length * 11, 160)
      const height = 16
      const box = {
        left: point.x + 8,
        right: point.x + 8 + width,
        top: point.y - height / 2,
        bottom: point.y + height / 2
      }

      if (!skipCollision) {
        const collides = placed.some((other) => {
          return !(box.right < other.left || box.left > other.right || box.bottom < other.top || box.top > other.bottom)
        })
        if (collides) return
        placed.push(box)
      }

      this.stationLabelGroup.addLayer(this.buildStationNameLabelMarker(entry, width, height))
    })
  }

  buildStationNameLabelMarker(entry, width, height) {
    const L = window.L

    return L.marker(entry.latlng, {
      interactive: false,
      keyboard: false,
      pane: this.stationLabelPane,
      zIndexOffset: 100 + (entry.priority || 1),
      icon: L.divIcon({
        className: "station-name-label-icon",
        html: `<span class="station-name-label">${this.escapeHtml(entry.name)}</span>`,
        iconSize: [ width, height ],
        iconAnchor: [ -8, height / 2 ]
      })
    })
  }

  terminalMarkerAt(latlng, color) {
    const L = window.L
    const safeColor = color || "#666666"
    const size = Math.max(this.stationMarkerRadius() + 4, 10)
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
    const { width, height } = this.transferStationMarkerDimensions()

    const html = `
      <div class="transfer-station-marker" style="width:${width}px;height:${height}px" aria-hidden="true">
        <div class="transfer-station-marker__half" style="background-color:${safeLeft}"></div>
        <div class="transfer-station-marker__half" style="background-color:${safeRight}"></div>
      </div>
    `

    const iconWidth = width + 4
    const iconHeight = height + 4

    return L.marker(latlng, {
      icon: L.divIcon({
        className: "transfer-station-icon",
        html,
        iconSize: [ iconWidth, iconHeight ],
        iconAnchor: [ iconWidth / 2, iconHeight / 2 ]
      }),
      pane: this.stationMarkerPane,
      zIndexOffset: 500
    })
  }

  transferStationMarkerDimensions() {
    const diameter = Math.max((this.stationMarkerRadius() * 2) + 2, 10)

    return {
      width: diameter + 2,
      height: Math.max(Math.round(diameter * 0.68), 8)
    }
  }

  transferStationRefs(ref) {
    if (!ref || !ref.includes(";")) return ref ? [ ref ] : []

    return ref.split(";").map((part) => part.trim()).filter(Boolean)
  }

  coordinateIndexRefs(routeId, ref) {
    const parts = this.transferStationRefs(ref)
    if (parts.length <= 1) return parts

    if (routeId === "taiwan_hsr") {
      return parts.filter((part) => /^\d{2}$/.test(part))
    }

    if (this.isTraRoute(routeId)) {
      return parts.filter((part) => /^\d{3,4}(-[A-Z]+)?$/.test(part))
    }

    return parts.filter((part) => !/^\d{3,4}(-[A-Z]+)?$/.test(part) && !/^\d{2}$/.test(part))
  }

  linePrefixForStationRef(stationRef) {
    return stationRef?.match(/^[A-Z]+/)?.[0] || null
  }

  traRouteForLineRef(lineRef) {
    return (this.routesManifest.tra || []).find((route) => route.ref === lineRef) || null
  }

  colorForStationRef(stationRef) {
    if (!stationRef) return null

    const junction = stationRef.match(/^(\d+)-([A-Z]+)$/)
    if (junction) {
      const lineRef = junction[2]
      const traRoute = this.traRouteForLineRef(lineRef)
      if (traRoute) return this.routeDisplayColor(traRoute) || traRoute.color || TRA_BRAND_COLOR

      const routes = this.routesForSystemRef("tra", lineRef)
      if (routes.length > 0) return this.routeDisplayColor(routes[0]) || routes[0].color

      return TRA_BRAND_COLOR
    }

    if (/^\d+$/.test(stationRef)) {
      if (stationRef.length <= 2) {
        const hsrRoutes = this.routesForSystemRef("hsr", "HSR")
        const hsrRoute = hsrRoutes[0] || (Array.isArray(this.routesManifest.hsr) ? this.routesManifest.hsr[0] : null)
        if (hsrRoute) return this.routeDisplayColor(hsrRoute) || hsrRoute.color || LAYER_COLORS.hsr
      }

      return TRA_BRAND_COLOR
    }

    if (/^G[1-6]$/i.test(stationRef)) {
      const maokongRoutes = this.routesForSystemRef("other", "MG")
      const maokong = maokongRoutes.find((route) => route.id === "maokong_gondola")
      if (maokong) return this.routeDisplayColor(maokong) || maokong.color
    }

    const prefix = this.linePrefixForStationRef(stationRef)
    if (!prefix) return null

    const routes = this.routesForLinePrefix(prefix)
    if (routes.length === 0) return null

    if (prefix === "A") {
      const visibleIds = new Set(this.visibleRouteLayerIds())
      if (visibleIds.has("airport_mrt_express") && !visibleIds.has("airport_mrt")) {
        const expressRoute = routes.find((route) => route.id === "airport_mrt_express")
        if (expressRoute) return EXPRESS_LINE_COLOR
      }

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
        iconSize: [ 16, 16 ],
        iconAnchor: [ 8, 8 ]
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
        iconSize: [ 14, 14 ],
        iconAnchor: [ 7, 7 ]
      }),
      pane: this.stationMarkerPane,
      zIndexOffset: 600
    })
  }

  stationMarkerRadius() {
    const zoom = this.map?.getZoom() ?? 12

    if (zoom <= 10) return 3
    if (zoom <= 12) return 4
    if (zoom <= 14) return 5

    return 6
  }

  circleMarkerAt(latlng, color) {
    const L = window.L

    return L.circleMarker(latlng, {
      radius: this.stationMarkerRadius(),
      fillColor: color,
      color: "#ffffff",
      weight: 1.5,
      opacity: 1,
      fillOpacity: 0.95,
      pane: this.stationMarkerPane
    })
  }

  bindFeaturePopup(feature, layer, routeId) {
    if (this.isRouteLineFeature(feature)) {
      this.bindRouteLinePopup(layer, routeId)
      return
    }

    const name = this.featureDisplayName(feature)
    if (!name) return

    const ref = feature.properties?.ref
    const line = routeId === "danhai_lrt"
      ? this.danhaiLineLabel(feature)
      : routeId === "taoyuan_airport_skytrain"
        ? this.skytrainLineLabel(feature)
        : feature.properties?.line
    const label = ref ? `${ref} ${name}` : name
    const subtitle = line ? `<br><span style="opacity:0.8">${line}</span>` : ""
    const terminalLabel = this.terminalStationLabel(feature)
    const terminalNote = terminalLabel ? `<br><span style="opacity:0.8">${terminalLabel}</span>` : ""
    const transferKind = ref ? this.transferKindByEndpointKey?.get(this.stationKey(routeId, ref)) : null
    const transferNote = transferKind
      ? `<br><span style="opacity:0.8">${this.transferNoteForKind(transferKind)}</span>`
      : this.isOutOfStationEndpoint(routeId, ref)
        ? `<br><span style="opacity:0.8">${this.t("popup.out_of_station")}</span>`
        : ""
    const expressNote = this.isAirportMrtExpressStop(ref) && (routeId === "airport_mrt" || routeId === "airport_mrt_express")
      ? `<br><span style="opacity:0.8">${this.t("popup.express_meet")}</span>`
      : feature.properties?.express_service
        ? `<br><span style="opacity:0.8">${this.t("popup.express_stop")}</span>`
        : ""
    const boardingAreaNote = feature.properties?.passenger_service === false
      ? ""
      : feature.properties?.boarding_area === "secured"
        ? `<br><span style="opacity:0.8">${this.t("popup.secured_boarding")}</span>`
        : feature.properties?.boarding_area === "public"
          ? `<br><span style="opacity:0.8">${this.t("popup.public_boarding")}</span>`
          : ""
    const directionNote = feature.properties?.note
      ? `<br><span style="opacity:0.8">${feature.properties.note}</span>`
      : ""
    const noPassengerServiceNote = feature.properties?.feature_type === "angle_station" ||
      feature.properties?.passenger_service === false
      ? `<br><span style="opacity:0.8">${this.t("popup.no_passenger")}</span>`
      : ""
    const popup = `<strong>${label}</strong>${subtitle}${terminalNote}${boardingAreaNote}${noPassengerServiceNote}${directionNote}${transferNote}${expressNote}`

    layer.bindPopup(() => {
      const board = this.stationBoardHtml(ref, routeId, name)
      return `${popup}${board}`
    }, { maxWidth: 320 })
    layer.on("popupopen", () => {
      this.bindStationBoardActions(layer.getPopup()?.getElement())
    })
  }

  isRouteLineFeature(feature) {
    const featureType = feature?.properties?.feature_type
    return featureType === "route" || featureType === "express_route"
  }

  bindRouteLinePopup(layer, routeId) {
    const route = this.findRoute(routeId)
    const name = this.escapeHtml(this.routeDisplayName(route) || routeId)
    const href = `/routes/${encodeURIComponent(routeId)}`
    const actionLabel = this.escapeHtml(this.t("popup.open_route_map"))
    const popup = `
      <div class="map-route-popup">
        <span class="map-route-popup__name">${name}</span>
        <a class="map-route-popup__action" href="${href}" data-turbo-frame="_top">${actionLabel}</a>
      </div>
    `

    layer.bindPopup(popup)
    if (typeof layer.setStyle === "function") {
      // Keep thin lines easier to click without changing visible weight much.
      layer.options.interactive = true
    }
  }

  escapeHtml(value) {
    return String(value || "")
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;")
      .replaceAll("'", "&#39;")
  }

  async fetchGeoJSON(url) {
    if (!this.geoJSONCache[url]) {
      this.geoJSONCache[url] = fetch(url, { cache: "no-cache" }).then(async (response) => {
        if (!response.ok) throw new Error(`Failed to load ${url}`)
        const data = await response.json()
        this.geoJSONDataByUrl[url] = data
        return data
      }).catch((error) => {
        delete this.geoJSONCache[url]
        throw error
      })
    }

    return this.geoJSONCache[url]
  }

  // ─── Vehicle layer ───────────────────────────────────────────────────────────

  syncSimulationFromScrubber() {
    const scrubberEl = document.querySelector("[data-controller~='time-scrubber']")
    const scrubber = scrubberEl
      ? this.application.getControllerForElementAndIdentifier(scrubberEl, "time-scrubber")
      : null

    if (scrubber?.at instanceof Date && !Number.isNaN(scrubber.at.getTime())) {
      this.simulationAt = scrubber.at.toISOString()
      this.simulationPlaying = Boolean(scrubber.playing)
      if (Number.isFinite(scrubber.playSpeed)) this.simulationSpeed = scrubber.playSpeed
    } else if (!this.simulationAt) {
      this.simulationAt = new Date().toISOString()
    }

    this.scheduleVehicleRefresh()
  }

  handleSimulationTime(event) {
    const at = event.detail?.at
    if (!at) return

    this.simulationAt = at
    if (typeof event.detail?.playing === "boolean") this.simulationPlaying = event.detail.playing
    if (Number.isFinite(event.detail?.speed)) this.simulationSpeed = event.detail.speed
    this.vehicleRefreshImmediate = Boolean(event.detail?.immediate) && !this.simulationPlaying

    if (this.simulationPlaying) {
      // One rAF loop owns marker + camera updates (railisland tick). Don't also
      // interpolate here or follow-cam setView runs twice per frame.
      this.ensureVehicleAnimationLoop()
      if (!this.vehicleRefreshTimer && !this.vehicleRefreshRunning) {
        this.scheduleVehicleRefresh()
      }
      return
    }

    // Scrub / pause: move with the clock immediately from the local snapshot.
    // Live overlay only corrects delay / GPS near wall-clock now.
    this.ensureScheduleSnapshots(this.visibleRouteLayerIds())
    this.refreshLocalFleet()
    this.scheduleVehicleRefresh()
    this.scheduleShareUrlUpdate()
  }

  minutesSinceMidnightFromIso(iso) {
    const date = new Date(iso)
    if (Number.isNaN(date.getTime())) return null

    // Simulation clock is Asia/Taipei (UTC+8, no DST).
    const totalMinutes = (date.getTime() / 60000) + (8 * 60)
    const dayMinutes = ((totalMinutes % 1440) + 1440) % 1440
    return dayMinutes
  }

  ensureVehicleAnimationLoop() {
    if (this.vehicleAnimFrame) return
    if (!this.simulationPlaying) return

    const step = (now) => {
      this.vehicleAnimFrame = null
      if (!this.simulationPlaying) return

      this.pullSimulationTimeFromScrubber()

      // railisland: camera setView every paint is the main follow jank source.
      // Throttle marker + camera to ~30fps; sim clock still advances every rAF.
      const minFrameMs = 33
      if (!this._vehicleDrawAt || now - this._vehicleDrawAt >= minFrameMs) {
        this._vehicleDrawAt = now
        this.refreshLocalFleet({ now })
        if (this.followCameraLocked) this.warmFollowTiles()
      }

      this.vehicleAnimFrame = window.requestAnimationFrame(step)
    }

    this.vehicleAnimFrame = window.requestAnimationFrame(step)
  }

  pullSimulationTimeFromScrubber() {
    const scrubberEl = document.querySelector("[data-controller~='time-scrubber']")
    if (!scrubberEl || !this.application) return

    const scrubber = this.application.getControllerForElementAndIdentifier(scrubberEl, "time-scrubber")
    if (!scrubber?.at) return

    this.simulationAt = scrubber.at.toISOString()
    this.simulationPlaying = Boolean(scrubber.playing)
    if (Number.isFinite(scrubber.playSpeed)) this.simulationSpeed = scrubber.playSpeed
  }

  stopVehicleAnimationLoop() {
    if (this.vehicleAnimFrame) {
      window.cancelAnimationFrame(this.vehicleAnimFrame)
      this.vehicleAnimFrame = null
    }
  }

  advanceVehicleMarkersLocally({ now = performance.now() } = {}) {
    this.refreshLocalFleet({ now })
  }

  refreshLocalFleet({ now = performance.now(), resync = false } = {}) {
    if (!this.simulationAt) return

    const date = this.simulationDateString()
    if (date && date !== this.scheduleDate) {
      this.scheduleSnapshots = {}
      this.scheduleDate = date
      this.ensureScheduleSnapshots(this.visibleRouteLayerIds())
    }

    const vehicles = this.buildLocalVehicles()
    if ((this.map?.getZoom() ?? 0) < VEHICLE_MIN_ZOOM) {
      this.clearVehicleMarkers()
      this.redrawVehicleCanvas([])
      this.notifyVehicleSummary(vehicles, { applied: Object.keys(this.liveOverlayByKey).length > 0 })
      return
    }

    const fleetKey = vehicles.map((vehicle) => String(vehicle.id)).sort().join(",")
    if (resync || fleetKey !== this._localFleetIds) {
      this._localFleetIds = fleetKey
      this.syncVehicleMarkers(vehicles)
    } else {
      this.advanceExistingMarkers(vehicles)
    }

    this.notifyVehicleSummary(vehicles, { applied: Object.keys(this.liveOverlayByKey).length > 0 })
    this.updateFollowCamera()
    this.redrawVehicleCanvas(vehicles)
    if (this.followedVehicleKey) this.syncFollowBar()
  }

  setVehicleMarkerVisible(marker, visible) {
    const el = marker?.getElement?.()
    if (el) el.style.visibility = visible ? "" : "hidden"
    if (typeof marker?.setOpacity === "function") marker.setOpacity(visible ? 1 : 0)
  }

  placeVehicleOnPath(vehicle, atMin) {
    const delayMin = (Number(vehicle.delay_seconds) || 0) / 60
    const clock = Number.isFinite(atMin) ? atMin - delayMin : atMin
    const path = Array.isArray(vehicle.path) ? vehicle.path : null
    if (path && path.length >= 2) {
      const placement = this.placementOnStopPath(path, clock, vehicle)
      if (!placement) return false
      this.applyVehiclePlacement(vehicle, placement)
      return true
    }

    const dep = Number(vehicle.motion_departure_minutes ?? vehicle.departure_minutes)
    const arr = Number(vehicle.motion_arrival_minutes ?? vehicle.arrival_minutes)
    if (!Number.isFinite(dep) || !Number.isFinite(arr)) return false

    if (vehicle.status === "stopped") {
      if (!this.withinSegmentMinutes(atMin, dep, arr) && atMin !== dep) return false
      vehicle.progress = 0
      return true
    }

    if (this.withinSegmentMinutes(atMin, dep, arr)) {
      vehicle.progress = this.segmentProgressMinutes(atMin, dep, arr)
      return true
    }

    const agePastArr = this.wrappedMinuteSpan(arr, atMin)
    const ageBeforeDep = this.wrappedMinuteSpan(atMin, dep)
    if (agePastArr <= ageBeforeDep && agePastArr < 30) {
      vehicle.progress = 1
      return true
    }

    return ageBeforeDep < 2
  }

  placementOnStopPath(path, atMin, vehicle = null) {
    for (let i = 0; i < path.length; i += 1) {
      const stop = path[i]
      const arrival = Number(stop.a)
      const departure = Number(stop.d)
      if (!Number.isFinite(arrival) || !Number.isFinite(departure)) continue

      if (arrival <= departure && atMin >= arrival && atMin < departure) {
        const next = path[i + 1] || stop
        return {
          fromRef: stop.r,
          toRef: next.r,
          fromName: stop.n,
          toName: next.n,
          progress: 0,
          stopped: true,
          departure: arrival,
          arrival: departure,
          motionDeparture: arrival,
          motionArrival: departure
        }
      }

      const next = path[i + 1]
      if (!next) continue

      const nextArrival = Number(next.a)
      if (!Number.isFinite(nextArrival)) continue
      if (!this.withinSegmentMinutes(atMin, departure, nextArrival)) continue

      const linear = this.segmentProgressMinutes(atMin, departure, nextArrival)
      return {
        fromRef: stop.r,
        toRef: next.r,
        fromName: stop.n,
        toName: next.n,
        fromKm: Number(stop.km),
        toKm: Number(next.km),
        progress: this.easedHopProgress(linear, vehicle),
        linear,
        stopped: false,
        departure,
        arrival: nextArrival,
        motionDeparture: departure,
        motionArrival: nextArrival
      }
    }

    return null
  }

  applyVehiclePlacement(vehicle, placement) {
    vehicle.from_station_ref = placement.fromRef
    vehicle.to_station_ref = placement.toRef
    if (placement.fromName) vehicle.from_station_name = placement.fromName
    if (placement.toName) vehicle.to_station_name = placement.toName
    vehicle.progress = placement.progress
    const delay = Number(vehicle.delay_seconds) || 0
    vehicle.status = placement.stopped ? "stopped" : (delay > 120 ? "delayed" : "on_time")
    vehicle.departure_minutes = placement.departure
    vehicle.arrival_minutes = placement.arrival
    vehicle.motion_departure_minutes = placement.motionDeparture
    vehicle.motion_arrival_minutes = placement.motionArrival
    vehicle.linear_progress = placement.linear ?? placement.progress
    if (Number.isFinite(placement.fromKm)) vehicle.from_km = placement.fromKm
    else delete vehicle.from_km
    if (Number.isFinite(placement.toKm)) vehicle.to_km = placement.toKm
    else delete vehicle.to_km

    const fromCoord = this.stationCoordForRef(placement.fromRef, vehicle.route_id)
    const toCoord = this.stationCoordForRef(placement.toRef, vehicle.route_id)
    if (fromCoord) {
      vehicle.from_lat = fromCoord[0]
      vehicle.from_lng = fromCoord[1]
    } else {
      delete vehicle.from_lat
      delete vehicle.from_lng
    }
    if (toCoord) {
      vehicle.to_lat = toCoord[0]
      vehicle.to_lng = toCoord[1]
    } else {
      delete vehicle.to_lat
      delete vehicle.to_lng
    }
  }

  handleSimulationSpeed(event) {
    if (typeof event.detail?.playing === "boolean") {
      this.simulationPlaying = event.detail.playing
      if (!this.simulationPlaying) this.stopVehicleAnimationLoop()
      else this.ensureVehicleAnimationLoop()
    }
    if (Number.isFinite(event.detail?.speed)) this.simulationSpeed = event.detail.speed
  }

  vehicleRefreshDebounceMs() {
    // Snapshot owns motion. Overlay fetch is only a near-now delay/GPS patch.
    if (!this.isNearLiveClock()) return 8000
    if (this.simulationPlaying) return 900
    if (this.vehicleRefreshImmediate) return 800
    return 700
  }

  scheduleVehicleRefresh() {
    if (this.booting) return
    if (this.vehicleRefreshTimer) clearTimeout(this.vehicleRefreshTimer)
    this.vehicleRefreshTimer = setTimeout(() => {
      this.vehicleRefreshTimer = null
      this.vehicleRefreshImmediate = false
      this.refreshVehicles()
    }, this.vehicleRefreshDebounceMs())
  }

  async refreshVehicles() {
    if (!this.mapReady || !this.map || !this.simulationAt) return

    if (this.vehicleRefreshRunning) {
      this.vehicleRefreshQueued = true
      return
    }

    this.vehicleRefreshRunning = true
    try {
      do {
        this.vehicleRefreshQueued = false
        await this.fetchAndSyncVehicles()
      } while (this.vehicleRefreshQueued)
    } finally {
      this.vehicleRefreshRunning = false
    }
  }

  async fetchAndSyncVehicles() {
    const routeIds = this.visibleRouteLayerIds()

    if (routeIds.length === 0) {
      this.clearVehicleMarkers()
      this.redrawVehicleCanvas([])
      this.notifyVehicleSummary([])
      return
    }

    await this.ensureScheduleSnapshots(routeIds)
    this.refreshLocalFleet()

    if (!this.isNearLiveClock()) {
      this.liveOverlayByKey = {}
      return
    }

    const requestAt = this.simulationAt
    if (!requestAt) return

    const params = new URLSearchParams({ at: requestAt })
    routeIds.forEach((id) => params.append("route_ids[]", id))

    if (this.vehicleFetchController) this.vehicleFetchController.abort()
    this.vehicleFetchController = new AbortController()
    const { signal } = this.vehicleFetchController
    const requestSeq = ++this.vehicleRequestSeq

    let data
    try {
      const response = await fetch(`/api/vehicles?${params}`, { signal })
      if (!response.ok) {
        console.warn("vehicles fetch HTTP", response.status)
        return
      }
      data = await response.json()
    } catch (error) {
      if (error?.name === "AbortError") return
      console.warn("vehicles fetch failed", error)
      return
    }

    if (requestSeq !== this.vehicleRequestSeq) {
      this.vehicleRefreshQueued = true
      return
    }

    this.mergeLiveOverlay(data.vehicles || [], data.live || {})
    this.refreshLocalFleet()

    if (this.simulationPlaying && this.isNearLiveClock() && !this.vehicleRefreshTimer && !this.vehicleRefreshQueued) {
      this.scheduleVehicleRefresh()
    }
  }

  syncVehicleMarkers(vehicles) {
    const nextIds = new Set()
    const softToId = {}
    vehicles.forEach((vehicle) => {
      const soft = String(vehicle.soft_id || vehicle.id || "")
      if (soft) softToId[soft] = String(vehicle.id || soft)
    })

    // Re-key existing markers when a hop rolls forward with the same soft_id.
    Object.entries(this.vehicleMarkersById).forEach(([id, marker]) => {
      const soft = String(marker._vehicleData?.soft_id || "")
      const nextId = softToId[soft]
      if (nextId && nextId !== id && !this.vehicleMarkersById[nextId]) {
        this.vehicleMarkersById[nextId] = marker
        delete this.vehicleMarkersById[id]
        marker._markerId = nextId
      }
    })

    const claimedMarkerIds = new Set()

    vehicles.forEach((vehicle) => {
      const id = String(vehicle.id || "")
      if (!id) return

      const onPath = this.applySimulationProgress(vehicle)
      const latlng = this.interpolateVehiclePosition(vehicle)
      if (!latlng) return

      nextIds.add(id)
      let existing = this.vehicleMarkersById[id]

      // Smooth handoff across metro station hops: reuse a nearby same-line marker.
      if (!existing) {
        existing = this.findHandoffMarker(vehicle, latlng, claimedMarkerIds)
        if (existing) {
          const oldId = existing._markerId
          if (oldId && this.vehicleMarkersById[oldId] === existing) {
            delete this.vehicleMarkersById[oldId]
          }
          this.vehicleMarkersById[id] = existing
          existing._markerId = id
        }
      }

      if (existing) {
        claimedMarkerIds.add(id)
        existing.setLatLng(latlng)
        existing._vehicleData = vehicle
        existing.setIcon(this.vehicleIconFor(vehicle, latlng))
        this.setVehicleMarkerVisible(existing, onPath !== false)
        if (this.followedMarker === existing) {
          this.followedVehicleKey = this.vehicleFollowKey(vehicle) || this.followedVehicleKey
          this.followedSoftId = String(vehicle.soft_id || this.followedSoftId || "") || null
          this.followLastLatLng = latlng
        }
        return
      }

      const marker = this.createVehicleMarker(vehicle, latlng)
      marker._markerId = id
      this.vehicleMarkersById[id] = marker
      this.vehicleGroup.addLayer(marker)
      this.setVehicleMarkerVisible(marker, onPath !== false)
      claimedMarkerIds.add(id)
    })

    Object.keys(this.vehicleMarkersById).forEach((id) => {
      if (nextIds.has(id)) return

      const marker = this.vehicleMarkersById[id]
      this.vehicleGroup.removeLayer(marker)
      delete this.vehicleMarkersById[id]
    })

    this.refreshFollowedMarkerStyles()
    this.tryAdoptPendingFollowVehicle()
    this.updateFollowCamera({ fromSync: true })
  }

  findHandoffMarker(vehicle, latlng, claimedMarkerIds) {
    const routeId = vehicle.route_id
    const direction = vehicle.direction
    const destination = vehicle.destination_name
    const soft = String(vehicle.soft_id || "")
    let softMatch = null
    let followedMatch = null
    let followedDistance = Infinity
    let nearMatch = null
    let nearDistance = 120

    Object.entries(this.vehicleMarkersById).forEach(([id, marker]) => {
      if (claimedMarkerIds.has(id)) return
      const data = marker._vehicleData
      if (!data) return
      if (data.route_id !== routeId || data.direction !== direction) return
      if (destination && data.destination_name && data.destination_name !== destination) return

      const distance = marker.getLatLng().distanceTo(latlng)
      const markerSoft = String(data.soft_id || "")

      if (soft && markerSoft && soft === markerSoft) {
        softMatch = marker
        return
      }

      // Keep the followed marker glued to its train across metro hops.
      if (this.followedMarker && marker === this.followedMarker && distance < 450) {
        if (distance < followedDistance) {
          followedDistance = distance
          followedMatch = marker
        }
        return
      }

      // Generic proximity handoff — never steal the followed marker for another train.
      if (this.followedMarker && marker === this.followedMarker) return
      if (distance < nearDistance) {
        nearDistance = distance
        nearMatch = marker
      }
    })

    return softMatch || followedMatch || nearMatch
  }

  applySimulationProgress(vehicle) {
    const atMin = this.minutesSinceMidnightFromIso(this.simulationAt)
    if (!Number.isFinite(atMin)) return true

    return this.placeVehicleOnPath(vehicle, atMin)
  }

  withinSegmentMinutes(minutes, a, b) {
    if (a <= b) return minutes >= a && minutes <= b
    return minutes >= a || minutes <= b
  }

  wrappedMinuteSpan(from, to) {
    const delta = ((to - from) % 1440 + 1440) % 1440
    return delta
  }

  segmentProgressMinutes(minutes, a, b) {
    if (a === b) return 0

    let segmentLen
    let offset
    if (a <= b) {
      segmentLen = b - a
      offset = minutes - a
    } else {
      segmentLen = (1440 - a) + b
      offset = minutes >= a ? (minutes - a) : (1440 - a + minutes)
    }

    if (segmentLen <= 0) return 0
    return Math.max(0, Math.min(1, offset / segmentLen))
  }

  clearVehicleMarkers() {
    if (this.vehicleGroup) this.vehicleGroup.clearLayers()
    this.vehicleMarkersById = {}
    this._localFleetIds = null
    if (this.followedVehicleKey) {
      if (!this.followHandoffPending()) {
        this.recordRideStamp({
          route_id: this.followedRouteId,
          train_number: this.followedTrainNumber,
          destination_name: this.followedDestination
        })
        this.followMissed = true
      }
      this.syncFollowBar()
    }
  }

  createVehicleMarker(vehicle, latlng) {
    const L = window.L
    const marker = L.marker(latlng, {
      icon: this.vehicleIconFor(vehicle, latlng),
      pane: "vehicles",
      interactive: !this.vehicleCanvas,
      zIndexOffset: 800
    })
    marker._vehicleData = vehicle
    marker.bindPopup(() => this.vehiclePopupHtml(marker._vehicleData || vehicle), { maxWidth: 280 })
    marker.on("popupopen", () => this.bindVehiclePopupActions(marker))
    return marker
  }

  bindVehiclePopupActions(marker) {
    const root = marker.getPopup()?.getElement()
    if (!root) return

    const followBtn = root.querySelector("[data-vehicle-follow]")
    if (followBtn && !followBtn._bound) {
      followBtn._bound = true
      followBtn.addEventListener("click", (event) => {
        event.preventDefault()
        event.stopPropagation()
        this.startFollowingVehicle(marker._vehicleData, marker)
        marker.closePopup()
      })
    }

    const stopBtn = root.querySelector("[data-vehicle-unfollow]")
    if (stopBtn && !stopBtn._bound) {
      stopBtn._bound = true
      stopBtn.addEventListener("click", (event) => {
        event.preventDefault()
        event.stopPropagation()
        this.stopFollowingVehicle()
        marker.closePopup()
      })
    }
  }

  vehicleStationLabel(vehicle, side) {
    const named = String(vehicle?.[`${side}_station_name`] || "").trim()
    if (this.isDisplayableStationName(named)) return named

    const ref = vehicle?.[`${side}_station_ref`]
    const resolved = this.stationNameForRef(ref, vehicle?.route_id)
    if (resolved) return resolved

    const raw = String(ref || "").trim()
    return this.isDisplayableStationName(raw) ? raw : "—"
  }

  stationNameForRef(ref, routeId) {
    if (!ref) return null

    const names = this.stationNameByKey || {}
    const tokens = [
      ...this.coordinateIndexRefs(routeId, ref),
      ...this.transferStationRefs(ref),
      ref
    ].filter(Boolean)

    for (const token of tokens) {
      if (routeId) {
        const direct = names[this.stationKey(routeId, token)]
        if (this.isDisplayableStationName(direct)) return direct
      }

      const suffix = `:${token}`
      const match = Object.entries(names).find(([ key, name ]) => (
        key.endsWith(suffix) && this.isDisplayableStationName(name)
      ))
      if (match) return match[1]
    }

    return null
  }

  vehicleFollowKey(vehicle) {
    if (!vehicle) return null
    // Prefer hard id for TRA/HSR trips; metro soft_id changes every hop so it is
    // only a hint — follow pins the marker object instead.
    return String(vehicle.id || vehicle.soft_id || "").trim() || null
  }

  isFollowingVehicle(vehicle) {
    if (!vehicle || !this.followedVehicleKey) return false
    if (this.followedMarker?._vehicleData === vehicle) return true
    if (String(vehicle.id || "") === this.followedVehicleKey) return true
    if (this.followedSoftId && String(vehicle.soft_id || "") === this.followedSoftId) return true
    return (
      this.followedRouteId === vehicle.route_id &&
      this.followedDirection === vehicle.direction &&
      this.followedDestination === vehicle.destination_name &&
      this.followedTrainNumber &&
      String(vehicle.train_number || "") === String(this.followedTrainNumber)
    )
  }

  startFollowingVehicle(vehicle, marker = null) {
    const key = this.vehicleFollowKey(vehicle)
    if (!key) return

    this.clearFollowHandoffState()
    this.followedMarker = marker || Object.values(this.vehicleMarkersById).find((item) => (
      item._vehicleData === vehicle || this.vehicleFollowKey(item._vehicleData) === key
    )) || null
    this.followedVehicleKey = key
    this.followedSoftId = String(vehicle.soft_id || "") || null
    this.followedTrainNumber = vehicle.train_number ? String(vehicle.train_number) : null
    this.followedRouteId = vehicle.route_id || null
    this.followedDirection = vehicle.direction || null
    this.followedDestination = vehicle.destination_name || null
    this.followCameraLocked = true
    this.followMissed = false
    this.followedLabel = this.vehicleLabel(vehicle)
    this.followedColor = this.normalizeHexColor(vehicle.color) || "#64748b"
    this.followLastLatLng = this.followedMarker?.getLatLng() || null

    this.refreshFollowedMarkerStyles()
    this.syncFollowBar()
    this.centerOnFollowedVehicle({ force: true, zoom: true })
    this.ensureScrubberPlaying()
    this.scheduleShareUrlUpdate()
  }

  stopFollowingVehicle({ silent = false } = {}) {
    this.followedMarker = null
    this.followedVehicleKey = null
    this.followedSoftId = null
    this.followedTrainNumber = null
    this.followedRouteId = null
    this.followedDirection = null
    this.followedDestination = null
    this.followLastLatLng = null
    this.followCameraLocked = false
    this.followMissed = false
    this.followedLabel = null
    this.followedColor = null
    this.clearFollowHandoffState()
    this.refreshFollowedMarkerStyles()
    if (!silent) this.syncFollowBar()
    else if (this.followBarEl) this.followBarEl.hidden = true
    this.scheduleShareUrlUpdate()
  }

  clearFollowHandoffState() {
    this.followHandoff = null
    this.followHandoffKey = null
    this.followHandoffDecision = null
    this.pendingFollowTripId = null
    this.pendingFollowTrainNumber = null
  }

  followHandoffPending() {
    if (this.pendingFollowTrainNumber) return true
    return Boolean(this.followHandoff?.train_number) && this.followHandoffDecision !== "no"
  }

  ensureScrubberPlaying() {
    const scrubberEl = document.querySelector("[data-controller~='time-scrubber']")
    if (!scrubberEl || !this.application) return

    const scrubber = this.application.getControllerForElementAndIdentifier(scrubberEl, "time-scrubber")
    if (!scrubber) return
    if (!scrubber.playing) scrubber.startPlayback()
  }

  findFollowedMarker() {
    if (!this.followedVehicleKey && !this.followedMarker) return null

    // 1) Pinned marker object still on the map.
    if (this.followedMarker) {
      const stillMounted = Object.values(this.vehicleMarkersById).includes(this.followedMarker)
      if (stillMounted) {
        const data = this.followedMarker._vehicleData
        if (data) {
          this.followedVehicleKey = this.vehicleFollowKey(data) || this.followedVehicleKey
          this.followedSoftId = String(data.soft_id || this.followedSoftId || "") || null
          this.followLastLatLng = this.followedMarker.getLatLng()
        }
        return this.followedMarker
      }
      this.followedMarker = null
    }

    // 2) Exact hard id.
    if (this.followedVehicleKey && this.vehicleMarkersById[this.followedVehicleKey]) {
      this.followedMarker = this.vehicleMarkersById[this.followedVehicleKey]
      return this.followedMarker
    }

    // 3) Soft id / train number identity.
    const match = Object.values(this.vehicleMarkersById).find((marker) => (
      this.isFollowingVehicle(marker._vehicleData)
    ))
    if (match) {
      this.followedMarker = match
      this.followLastLatLng = match.getLatLng()
      return match
    }

    // 4) Nearest same-line candidate near last known position (metro hop recovery).
    if (!this.followLastLatLng || !this.followedRouteId) return null

    let best = null
    let bestDistance = 500
    Object.values(this.vehicleMarkersById).forEach((marker) => {
      const data = marker._vehicleData
      if (!data) return
      if (data.route_id !== this.followedRouteId) return
      if (this.followedDirection && data.direction !== this.followedDirection) return
      if (this.followedDestination && data.destination_name && data.destination_name !== this.followedDestination) return
      const distance = marker.getLatLng().distanceTo(this.followLastLatLng)
      if (distance < bestDistance) {
        bestDistance = distance
        best = marker
      }
    })

    if (best) {
      this.followedMarker = best
      this.followedVehicleKey = this.vehicleFollowKey(best._vehicleData) || this.followedVehicleKey
      this.followedSoftId = String(best._vehicleData?.soft_id || this.followedSoftId || "") || null
      this.followLastLatLng = best.getLatLng()
    }
    return best
  }

  refreshFollowedMarkerStyles() {
    Object.values(this.vehicleMarkersById).forEach((marker) => {
      const following = this.followedMarker
        ? marker === this.followedMarker
        : this.isFollowingVehicle(marker._vehicleData)
      const el = marker.getElement()
      el?.classList.toggle("vehicle-marker--following", following)
      marker.setZIndexOffset(following ? 1200 : 800)
    })
  }

  updateFollowCamera({ fromSync = false } = {}) {
    if (!this.followedVehicleKey && !this.followedMarker) return

    const marker = this.findFollowedMarker()
    if (!marker) {
      if (this.followHandoffPending()) {
        if (fromSync) this.syncFollowBar()
        return
      }
      if (fromSync && !this.followMissed) {
        this.recordRideStamp({
          route_id: this.followedRouteId,
          train_number: this.followedTrainNumber,
          destination_name: this.followedDestination
        })
        this.followMissed = true
        this.syncFollowBar()
      }
      return
    }

    this.maybeArmFollowHandoff(marker._vehicleData)

    if (this.followMissed) {
      this.followMissed = false
      this.syncFollowBar()
    } else if (fromSync) {
      this.syncFollowBar()
    }

    if (this.followCameraLocked) this.centerOnFollowedVehicle()
  }

  centerOnFollowedVehicle({ force = false, zoom = false } = {}) {
    if (!this.map) return
    const marker = this.findFollowedMarker()
    if (!marker) return

    const latlng = marker.getLatLng()
    if (!latlng) return
    this.followLastLatLng = latlng

    const targetZoom = zoom
      ? Math.max(this.map.getZoom() ?? 0, VEHICLE_TAG_ZOOM)
      : this.map.getZoom()

    // Match railisland recenterTo: skip setView when already centered (dwell/pause).
    // Repeated setView(animate:false) is their documented follow jank source.
    if (!force && !zoom && this.followCameraAlreadyCentered(latlng, targetZoom)) return

    this._autoPan = true
    this.ignoreMapViewEvents = true
    try {
      this.map.setView(latlng, targetZoom, { animate: false })
    } finally {
      this.ignoreMapViewEvents = false
      this._autoPan = false
    }
  }

  followCameraAlreadyCentered(latlng, zoom) {
    if (!this.map) return false
    const currentZoom = this.map.getZoom()
    if (Number.isFinite(zoom) && Number.isFinite(currentZoom) && Math.abs(currentZoom - zoom) > 0.01) {
      return false
    }

    const current = this.map.getCenter()
    if (!current) return false

    return Math.abs(current.lat - latlng.lat) < 1e-6 && Math.abs(current.lng - latlng.lng) < 1e-6
  }

  moveVehicleMarker(marker, latlng) {
    if (!marker || !latlng) return
    const current = marker.getLatLng()
    if (current && current.distanceTo(latlng) < 0.4) return
    marker.setLatLng(latlng)
  }

  ensureFollowBar() {
    if (this.followBarEl) return

    const el = document.createElement("div")
    el.className = "vehicle-follow-bar"
    el.hidden = true
    el.innerHTML = `
      <div class="vehicle-follow-bar__row">
        <span class="vehicle-follow-bar__dot" aria-hidden="true"></span>
        <div class="vehicle-follow-bar__copy">
          <strong class="vehicle-follow-bar__title"></strong>
          <span class="vehicle-follow-bar__meta"></span>
        </div>
        <button type="button" class="vehicle-follow-bar__btn vehicle-follow-bar__recenter" hidden></button>
        <button type="button" class="vehicle-follow-bar__btn vehicle-follow-bar__stop"></button>
      </div>
      <div class="vehicle-follow-bar__handoff" hidden>
        <p class="vehicle-follow-bar__handoff-msg"></p>
        <div class="vehicle-follow-bar__handoff-actions">
          <button type="button" class="vehicle-follow-bar__btn vehicle-follow-bar__handoff-yes" data-follow-handoff="yes"></button>
          <button type="button" class="vehicle-follow-bar__btn vehicle-follow-bar__handoff-no" data-follow-handoff="no"></button>
        </div>
      </div>
    `
    const host = this.hasMapTarget
      ? (this.mapTarget.parentElement || this.mapTarget)
      : this.element
    host.appendChild(el)
    this.followBarEl = el

    el.querySelector(".vehicle-follow-bar__stop")?.addEventListener("click", () => {
      this.stopFollowingVehicle()
    })
    el.querySelector(".vehicle-follow-bar__recenter")?.addEventListener("click", () => {
      this.followCameraLocked = true
      this.followMissed = false
      this.centerOnFollowedVehicle({ force: true, zoom: true })
      this.syncFollowBar()
    })
    el.querySelector("[data-follow-handoff='yes']")?.addEventListener("click", () => {
      this.acceptFollowHandoff()
    })
    el.querySelector("[data-follow-handoff='no']")?.addEventListener("click", () => {
      this.rejectFollowHandoff()
    })
  }

  syncFollowBar() {
    this.ensureFollowBar()
    const el = this.followBarEl
    if (!el) return

    if (!this.followedVehicleKey) {
      el.hidden = true
      return
    }

    el.hidden = false
    el.classList.toggle("vehicle-follow-bar--miss", Boolean(this.followMissed) && !this.followHandoffPending())
    el.classList.toggle("vehicle-follow-bar--unlocked", !this.followCameraLocked && !this.followMissed)

    const marker = this.findFollowedMarker()
    const vehicle = marker?._vehicleData
    if (vehicle) this.maybeArmFollowHandoff(vehicle)
    const title = vehicle ? this.vehicleLabel(vehicle) : (this.followedLabel || this.t("time_scrubber.follow_train"))
    const color = this.normalizeHexColor(vehicle?.color || this.followedColor) || "#64748b"

    const titleEl = el.querySelector(".vehicle-follow-bar__title")
    const metaEl = el.querySelector(".vehicle-follow-bar__meta")
    const dotEl = el.querySelector(".vehicle-follow-bar__dot")
    const recenterBtn = el.querySelector(".vehicle-follow-bar__recenter")
    const stopBtn = el.querySelector(".vehicle-follow-bar__stop")
    const handoffEl = el.querySelector(".vehicle-follow-bar__handoff")
    const handoffMsg = el.querySelector(".vehicle-follow-bar__handoff-msg")
    const handoffYes = el.querySelector("[data-follow-handoff='yes']")
    const handoffNo = el.querySelector("[data-follow-handoff='no']")
    const showHandoff = Boolean(this.followHandoff?.train_number) && !this.followHandoffDecision

    el.classList.toggle("vehicle-follow-bar--handoff", showHandoff || Boolean(this.pendingFollowTrainNumber))

    if (titleEl) titleEl.textContent = title
    if (dotEl) dotEl.style.background = color
    if (stopBtn) stopBtn.textContent = this.t("time_scrubber.unfollow")

    if (recenterBtn) {
      recenterBtn.hidden = this.followCameraLocked || this.followMissed
      recenterBtn.textContent = this.t("time_scrubber.follow_recenter")
    }

    if (handoffEl) {
      handoffEl.hidden = !showHandoff
      if (showHandoff && handoffMsg) {
        handoffMsg.textContent = this.t("time_scrubber.follow_handoff", { number: this.followHandoff.train_number })
      }
      if (handoffYes) handoffYes.textContent = this.t("time_scrubber.follow_handoff_yes")
      if (handoffNo) handoffNo.textContent = this.t("time_scrubber.follow_handoff_no")
    }

    if (metaEl) {
      if (this.pendingFollowTrainNumber && !vehicle) {
        metaEl.textContent = this.t("time_scrubber.follow_handoff_waiting", { number: this.pendingFollowTrainNumber })
      } else if (this.followMissed && !showHandoff) {
        metaEl.textContent = this.t("time_scrubber.follow_ended")
      } else if (!this.followCameraLocked && !showHandoff) {
        metaEl.textContent = this.t("time_scrubber.follow_unlocked")
      } else if (vehicle) {
        const fromName = this.vehicleStationLabel(vehicle, "from")
        const toName = this.vehicleStationLabel(vehicle, "to")
        const extras = []
        const journey = this.followJourneyKm(vehicle)
        if (Number.isFinite(journey)) extras.push(this.t("time_scrubber.journey_km", { km: journey.toFixed(1) }))
        const speed = this.followSpeedKmh(vehicle)
        if (Number.isFinite(speed) && speed > 1) extras.push(this.t("time_scrubber.speed_kmh", { speed: Math.round(speed) }))
        const segment = this.t("time_scrubber.segment", { from: fromName, to: toName })
        metaEl.textContent = extras.length ? `${segment} · ${extras.join(" · ")}` : segment
      } else {
        metaEl.textContent = this.t("time_scrubber.follow_tracking")
      }
    }
  }

  maybeArmFollowHandoff(vehicle) {
    const next = vehicle?.continues_as
    const number = String(next?.train_number || "").trim()
    if (!number || !this.followedVehicleKey) return

    const key = `${this.vehicleFollowKey(vehicle) || this.followedVehicleKey}->${next.trip_id || number}`
    if (this.followHandoffKey === key) return
    if (this.followHandoffDecision === "yes" || this.followHandoffDecision === "no") return

    this.followHandoffKey = key
    this.followHandoff = {
      train_number: number,
      trip_id: next.trip_id || null,
      route_id: next.route_id || null
    }
    this.followHandoffDecision = null
  }

  async acceptFollowHandoff() {
    const next = this.followHandoff
    if (!next?.train_number) return

    this.followHandoffDecision = "yes"
    this.pendingFollowTripId = next.trip_id ? `trip:${next.trip_id}` : null
    this.pendingFollowTrainNumber = String(next.train_number)
    this.followedTrainNumber = this.pendingFollowTrainNumber
    this.followedSoftId = this.pendingFollowTripId
    this.followedDestination = null
    this.followMissed = false
    this.followHandoff = null
    if (next.route_id) this.followedRouteId = next.route_id

    if (next.route_id && !this.layerVisible[next.route_id]) {
      await this.setRouteLayersVisible([next.route_id], true, { fitBounds: false })
    }

    if (!this.tryAdoptPendingFollowVehicle()) {
      this.vehicleRefreshImmediate = true
      this.scheduleVehicleRefresh()
      this.syncFollowBar()
    }
  }

  rejectFollowHandoff() {
    this.followHandoffDecision = "no"
    this.followHandoff = null
    this.stopFollowingVehicle()
  }

  tryAdoptPendingFollowVehicle() {
    if (!this.pendingFollowTripId && !this.pendingFollowTrainNumber) return false

    const marker = Object.values(this.vehicleMarkersById).find((item) => {
      const data = item._vehicleData
      if (!data) return false
      if (this.pendingFollowTripId && String(data.id) === String(this.pendingFollowTripId)) return true
      return this.pendingFollowTrainNumber && String(data.train_number || "") === String(this.pendingFollowTrainNumber)
    })
    if (!marker) return false

    this.startFollowingVehicle(marker._vehicleData, marker)
    return true
  }

  vehicleIconFor(vehicle, latlng = null) {
    const L = window.L
    if (this.vehicleCanvas) {
      return L.divIcon({
        className: "leaflet-div-icon vehicle-marker-icon vehicle-marker-icon--ghost",
        html: "",
        iconSize: [ 12, 12 ],
        iconAnchor: [ 6, 6 ]
      })
    }

    const zoom = this.map?.getZoom() ?? 12
    const color = this.normalizeHexColor(vehicle.color) || "#64748b"
    const status = vehicle.status || "on_time"
    const fg = this.contrastTextColor(color)
    const isHsr = this.isHsrVehicle(vehicle)
    const labelText = this.vehicleLabel(vehicle)

    if (zoom < VEHICLE_TAG_ZOOM) {
      const size = zoom <= 9 ? 10 : 14
      return L.divIcon({
        className: "leaflet-div-icon vehicle-marker-icon",
        html: `<div class="vehicle-dot vehicle-dot--${this.escapeHtml(status)}${isHsr ? " vehicle-dot--hsr" : ""}" style="--vehicle-color:${this.escapeHtml(color)};width:${size}px;height:${size}px"></div>`,
        iconSize: [ size, size ],
        iconAnchor: [ size / 2, size / 2 ]
      })
    }

    const bearing = this.vehicleBearingDegrees(vehicle, latlng)
    const approxW = Math.max(isHsr ? 34 : 28, String(labelText).length * (isHsr ? 7.5 : 9) + 14)
    const box = Math.max(approxW + 12, 28)
    const shortTurn = this.isShortTurnVehicle(vehicle)

    const tagClass = [
      "vehicle-tag",
      isHsr ? "vehicle-tag--hsr" : "",
      shortTurn ? "vehicle-tag--short-turn" : "",
      `vehicle-tag--${status}`
    ].filter(Boolean).join(" ")

    return L.divIcon({
      className: "leaflet-div-icon vehicle-marker-icon",
      html: `<div class="${tagClass}" style="--vehicle-color:${this.escapeHtml(color)};--vehicle-fg:${this.escapeHtml(fg)};--vehicle-bearing:${bearing}deg"><span class="vehicle-tag__label">${this.escapeHtml(labelText)}</span><span class="vehicle-tag__arrow" aria-hidden="true"></span></div>`,
      iconSize: [ box, box ],
      iconAnchor: [ box / 2, box / 2 ]
    })
  }

  vehicleLabel(vehicle) {
    if (this.isMetroVehicle(vehicle)) {
      const dest = String(vehicle.label || vehicle.destination_name || "").trim()
      if (dest) return dest
    }

    const num = String(vehicle.train_number || vehicle.label || "").trim()
    if (num) return num

    const route = this.findRoute(vehicle.route_id)
    const name = this.routeDisplayName(route)
    if (name) {
      const shortened = name.replace(/線$/, "").replace(/輕軌$/, "").replace(/捷運$/, "")
      if (/[\u4e00-\u9fff]/.test(shortened)) return shortened.slice(0, 2)
      return shortened.slice(0, 4)
    }

    return String(vehicle.route_id || "列車").slice(0, 4)
  }

  isShortTurnVehicle(vehicle) {
    return vehicle.service_kind === "short_turn" || String(vehicle.label || "").startsWith("往")
  }

  isMetroVehicle(vehicle) {
    const systemId = String(vehicle.system_id || "")
    return systemId.includes("metro") || systemId.endsWith("_lrt") || systemId === "lrt"
  }

  isHsrVehicle(vehicle) {
    return vehicle.system_id === "hsr" || vehicle.system_id === "taiwan_hsr" || vehicle.route_id === "taiwan_hsr"
  }

  normalizeHexColor(color) {
    if (!color) return null
    const value = String(color).trim()
    if (/^#[0-9a-fA-F]{6}$/.test(value)) return value
    if (/^#[0-9a-fA-F]{3}$/.test(value)) {
      return `#${value[1]}${value[1]}${value[2]}${value[2]}${value[3]}${value[3]}`
    }
    return value
  }

  contrastTextColor(hex) {
    const normalized = this.normalizeHexColor(hex)
    if (!normalized || !/^#[0-9a-fA-F]{6}$/.test(normalized)) return "#fff"

    const r = Number.parseInt(normalized.slice(1, 3), 16)
    const g = Number.parseInt(normalized.slice(3, 5), 16)
    const b = Number.parseInt(normalized.slice(5, 7), 16)
    return (0.299 * r + 0.587 * g + 0.114 * b) > 150 ? "#111111" : "#ffffff"
  }

  vehicleBearingDegrees(vehicle, latlng = null) {
    const fromCoord = this.stationCoordForRef(vehicle.from_station_ref, vehicle.route_id) ||
      (Number.isFinite(vehicle.from_lat) ? [ vehicle.from_lat, vehicle.from_lng ] : null)
    const toCoord = this.stationCoordForRef(vehicle.to_station_ref, vehicle.route_id) ||
      (Number.isFinite(vehicle.to_lat) ? [ vehicle.to_lat, vehicle.to_lng ] : null)
    if (!fromCoord || !toCoord) return 0

    // Prefer track tangent near the vehicle when available.
    if (latlng) {
      const tracks = this.vehicleTracksFor(vehicle.route_id)
      const tangent = tracks?.length ? this.trackBearingNear(latlng, tracks) : null
      if (Number.isFinite(tangent)) return tangent
    }

    return this.vehiclePairBearingDegrees(fromCoord, toCoord)
  }

  trackBearingNear(latlng, tracks) {
    const L = window.L
    let best = null
    let bestDistance = Infinity

    for (const coords of tracks) {
      if (!coords || coords.length < 2) continue

      for (let i = 0; i < coords.length - 1; i += 1) {
        const a = L.latLng(coords[i][1], coords[i][0])
        const b = L.latLng(coords[i + 1][1], coords[i + 1][0])
        const mid = L.latLng((a.lat + b.lat) / 2, (a.lng + b.lng) / 2)
        const distance = latlng.distanceTo(mid)
        if (distance >= bestDistance) continue

        bestDistance = distance
        best = this.vehiclePairBearingDegrees([ a.lat, a.lng ], [ b.lat, b.lng ])
      }
    }

    return bestDistance < 400 ? best : null
  }

  vehiclePairBearingDegrees(fromCoord, toCoord) {
    const lat1 = (fromCoord[0] * Math.PI) / 180
    const lat2 = (toCoord[0] * Math.PI) / 180
    const dLng = ((toCoord[1] - fromCoord[1]) * Math.PI) / 180
    const y = Math.sin(dLng) * Math.cos(lat2)
    const x = Math.cos(lat1) * Math.sin(lat2) - Math.sin(lat1) * Math.cos(lat2) * Math.cos(dLng)
    return ((Math.atan2(y, x) * 180) / Math.PI + 360) % 360
  }

  interpolateVehiclePosition(vehicle) {
    const L = window.L
    if (!L) return null

    if (Number.isFinite(vehicle.lat) && Number.isFinite(vehicle.lng) && vehicle.position_source === "tdx_gps") {
      return L.latLng(vehicle.lat, vehicle.lng)
    }

    const progress = vehicle.progress ?? 0
    const chainPoint = this.chainagePointForVehicle(vehicle, progress)
    if (chainPoint) return L.latLng(chainPoint.lat, chainPoint.lng)

    const tracks = this.vehicleTracksFor(vehicle.route_id)

    let fromCoord = null
    let toCoord = null

    if (Number.isFinite(vehicle.from_lat) && Number.isFinite(vehicle.from_lng) &&
        Number.isFinite(vehicle.to_lat) && Number.isFinite(vehicle.to_lng)) {
      fromCoord = [ vehicle.from_lat, vehicle.from_lng ]
      toCoord = [ vehicle.to_lat, vehicle.to_lng ]
    } else {
      fromCoord = this.stationCoordForRef(vehicle.from_station_ref, vehicle.route_id)
      toCoord = this.stationCoordForRef(vehicle.to_station_ref, vehicle.route_id)
    }

    // Dwell / hop endpoints: snap to the station instead of scanning the full polyline.
    if (fromCoord && (progress <= 0 || vehicle.status === "stopped")) {
      return L.latLng(fromCoord[0], fromCoord[1])
    }
    if (toCoord && progress >= 1) {
      return L.latLng(toCoord[0], toCoord[1])
    }

    if (fromCoord && toCoord && tracks.length > 0) {
      const interpolated = this.interpolateAlongTracks(fromCoord, toCoord, progress, tracks)
      if (interpolated) return interpolated
    }

    if (fromCoord && toCoord) {
      const lat = fromCoord[0] + (toCoord[0] - fromCoord[0]) * progress
      const lng = fromCoord[1] + (toCoord[1] - fromCoord[1]) * progress
      return L.latLng(lat, lng)
    }

    if (Number.isFinite(vehicle.lat) && Number.isFinite(vehicle.lng)) {
      return L.latLng(vehicle.lat, vehicle.lng)
    }

    return null
  }

  stationCoordForRef(ref, routeId) {
    if (!ref || !routeId) return null

    const latlng = this.stationLatLng(routeId, ref)
    if (latlng) return [ latlng.lat, latlng.lng ]

    const byRoute = this.stationCoordsByRouteRef[routeId]
    if (!byRoute) return null

    if (byRoute[ref]) return [ byRoute[ref].lat, byRoute[ref].lng ]

    for (const part of this.transferStationRefs(ref)) {
      if (byRoute[part]) return [ byRoute[part].lat, byRoute[part].lng ]
    }

    const token = this.transferStationRefs(ref)[0]
    if (!token) return null

    const matchKey = Object.keys(byRoute).find((key) => {
      return key === token || this.transferStationRefs(key).includes(token)
    })
    if (!matchKey) return null

    return [ byRoute[matchKey].lat, byRoute[matchKey].lng ]
  }

  interpolateAlongTracks(fromCoord, toCoord, progress, tracks) {
    const L = window.L
    let best = null
    let bestScore = Infinity

    for (const coords of tracks) {
      if (!coords || coords.length < 2) continue

      const fromHit = this.chainHitForPoint(fromCoord[0], fromCoord[1], coords)
      const toHit = this.chainHitForPoint(toCoord[0], toCoord[1], coords)
      if (!fromHit || !toHit) continue

      // Reject tracks that don't actually pass near both stations (e.g. depot stubs).
      if (fromHit.distanceMeters > 250 || toHit.distanceMeters > 250) continue

      const spanMeters = Math.abs(toHit.distanceAlong - fromHit.distanceAlong)
      if (spanMeters < 40) continue

      // Prefer accurate snaps and a real inter-station span.
      const score = fromHit.distanceMeters + toHit.distanceMeters - (spanMeters * 0.001)
      if (score >= bestScore) continue

      bestScore = score
      best = { coords, fromHit, toHit }
    }

    if (!best) return null

    const targetAlong =
      best.fromHit.distanceAlong +
      ((best.toHit.distanceAlong - best.fromHit.distanceAlong) * Math.max(0, Math.min(1, progress)))

    const point = this.pointAlongPolyline(best.coords, targetAlong)
    if (!point) return null

    return L.latLng(point[1], point[0])
  }

  chainHitForPoint(lat, lon, coordinates) {
    let best = null
    let traveled = 0

    for (let segmentIndex = 0; segmentIndex < coordinates.length - 1; segmentIndex += 1) {
      const start = coordinates[segmentIndex]
      const finish = coordinates[segmentIndex + 1]
      const projection = this.projectLonLatOnSegment(lon, lat, start, finish)
      const segMeters = this.haversineMeters(start[1], start[0], finish[1], finish[0])
      const distanceAlong = traveled + (segMeters * projection.progress)
      const distanceMeters = this.haversineMeters(lat, lon, projection.projectedY, projection.projectedX)

      if (!best || distanceMeters < best.distanceMeters) {
        best = {
          index: segmentIndex + projection.progress,
          distanceAlong,
          distanceMeters
        }
      }

      traveled += segMeters
    }

    return best
  }

  pointAlongPolyline(coordinates, targetMeters) {
    if (!coordinates || coordinates.length < 2) return null

    let traveled = 0
    const total = this.polylineLengthMeters(coordinates)
    const target = Math.max(0, Math.min(total, targetMeters))

    for (let i = 0; i < coordinates.length - 1; i += 1) {
      const start = coordinates[i]
      const finish = coordinates[i + 1]
      const seg = this.haversineMeters(start[1], start[0], finish[1], finish[0])
      if (traveled + seg >= target || i === coordinates.length - 2) {
        const ratio = seg > 0 ? Math.max(0, Math.min(1, (target - traveled) / seg)) : 0
        return [
          start[0] + ((finish[0] - start[0]) * ratio),
          start[1] + ((finish[1] - start[1]) * ratio)
        ]
      }
      traveled += seg
    }

    return coordinates[coordinates.length - 1]
  }

  polylineLengthMeters(coordinates) {
    let total = 0
    for (let i = 0; i < coordinates.length - 1; i += 1) {
      const a = coordinates[i]
      const b = coordinates[i + 1]
      total += this.haversineMeters(a[1], a[0], b[1], b[0])
    }
    return total
  }

  haversineMeters(lat1, lon1, lat2, lon2) {
    const toRad = Math.PI / 180
    const dLat = (lat2 - lat1) * toRad
    const dLon = (lon2 - lon1) * toRad
    const a =
      Math.sin(dLat / 2) ** 2 +
      Math.cos(lat1 * toRad) * Math.cos(lat2 * toRad) * Math.sin(dLon / 2) ** 2
    return 2 * 6378137 * Math.asin(Math.min(1, Math.sqrt(a)))
  }

  vehiclePopupHtml(vehicle) {
    const color = vehicle.color || "#64748b"
    const source = vehicle.position_source || "unknown"
    const sourceLabel =
      source === "timetable" ? this.t("time_scrubber.source_timetable") :
      source === "station_timetable" ? this.t("time_scrubber.source_station_timetable") :
      source === "headway_estimate" ? this.t("time_scrubber.source_headway") :
      source === "timetable+live" ? this.t("time_scrubber.source_timetable_live") :
      source === "station_timetable+live" ? this.t("time_scrubber.source_station_timetable_live") :
      source === "headway_estimate+live" ? this.t("time_scrubber.source_headway_live") :
      source === "tdx_gps" ? this.t("time_scrubber.source_gps") :
      this.t("time_scrubber.source_unknown")

    const delaySource = vehicle.delay_source || "none"
    const delayLabel =
      delaySource === "tdx_tra" ? this.t("time_scrubber.source_live_tra") :
      delaySource === "tdx_metro_liveboard" ? this.t("time_scrubber.source_live_metro") :
      null

    const liveApplied = String(source).includes("live") || source === "tdx_gps" || String(delaySource).startsWith("tdx")
    const note = liveApplied
      ? this.t("time_scrubber.live_note")
      : this.t("time_scrubber.synthetic_note")

    const route = this.findRoute(vehicle.route_id)
    const routeName = this.routeDisplayName(route) || vehicle.route_id || "—"
    const title = this.isMetroVehicle(vehicle)
      ? (vehicle.label || this.t("time_scrubber.destination", { name: String(vehicle.destination_name || this.t("time_scrubber.no_train")) }))
      : this.t("time_scrubber.train_number", { number: String(vehicle.train_number || vehicle.label || this.t("time_scrubber.no_train")) })

    const fromName = this.vehicleStationLabel(vehicle, "from")
    const toName = this.vehicleStationLabel(vehicle, "to")
    const direction = vehicle.direction ? String(vehicle.direction) : ""
    const shortTurnNote = this.isShortTurnVehicle(vehicle)
      ? `<div style="font-size:0.75rem;color:#b45309;margin-top:2px">${this.escapeHtml(this.t("time_scrubber.short_turn"))}</div>`
      : ""

    const delaySeconds = Number(vehicle.delay_seconds) || 0
    let delayLine = ""
    if (Math.abs(delaySeconds) >= 120) {
      const minutes = Math.round(Math.abs(delaySeconds) / 60)
      delayLine = delaySeconds > 0
        ? this.t("time_scrubber.delay_minutes", { minutes })
        : this.t("time_scrubber.early_minutes", { minutes })
    }

    const lines = [
      `<div style="font-weight:600;margin-bottom:4px">
        <span style="display:inline-block;width:8px;height:8px;border-radius:50%;background:${this.escapeHtml(color)};margin-right:4px;vertical-align:middle"></span>
        ${this.escapeHtml(title)}
      </div>`,
      shortTurnNote,
      `<div style="font-size:0.8rem;color:#475569">${this.escapeHtml(this.t("time_scrubber.route", { name: routeName }))}</div>`
    ]

    if (direction) {
      lines.push(`<div style="font-size:0.8rem;color:#475569">${this.escapeHtml(this.t("time_scrubber.direction", { name: direction }))}</div>`)
    }

    lines.push(
      `<div style="font-size:0.8rem;color:#475569;margin-top:2px">${this.escapeHtml(this.t("time_scrubber.segment", { from: fromName, to: toName }))}</div>`
    )

    if (delayLine) {
      lines.push(`<div style="font-size:0.8rem;color:#b45309;margin-top:4px">${this.escapeHtml(delayLine)}</div>`)
    }

    const continuesAs = String(vehicle.continues_as?.train_number || "").trim()
    if (continuesAs) {
      lines.push(`<div style="font-size:0.8rem;color:#b45309;margin-top:4px">${this.escapeHtml(this.t("time_scrubber.follow_handoff", { number: continuesAs }))}</div>`)
    }

    lines.push(
      `<div style="font-size:0.75rem;margin-top:6px;color:#64748b">${this.escapeHtml(sourceLabel)}</div>`
    )
    if (delayLabel) {
      lines.push(`<div style="font-size:0.7rem;color:#64748b">${this.escapeHtml(delayLabel)}</div>`)
    }
    lines.push(
      `<div style="font-size:0.7rem;color:#94a3b8;margin-top:6px">${this.escapeHtml(note)}</div>`
    )

    const following = this.isFollowingVehicle(vehicle)
    lines.push(
      `<button type="button" class="vehicle-follow-popup-btn" data-vehicle-${following ? "unfollow" : "follow"} style="margin-top:8px;width:100%;border:1px solid #cbd5e1;background:#f8fafc;border-radius:0.4rem;padding:0.35rem 0.5rem;font-size:0.75rem;cursor:pointer">
        ${this.escapeHtml(following ? this.t("time_scrubber.unfollow") : this.t("time_scrubber.follow_train"))}
      </button>`
    )

    return `<div style="min-width:180px">${lines.join("")}</div>`
  }

  notifyVehicleSummary(vehicles, liveMeta = {}) {
    const count = vehicles.length
    const live = Boolean(liveMeta.applied) || vehicles.some((vehicle) => {
      const source = String(vehicle.position_source || "")
      const delay = String(vehicle.delay_source || "")
      return source.includes("live") || source === "tdx_gps" || delay.startsWith("tdx")
    })

    const scrubberEl = document.querySelector("[data-controller~='time-scrubber']")
    if (scrubberEl) {
      const scrubber = this.application.getControllerForElementAndIdentifier(scrubberEl, "time-scrubber")
      if (scrubber) scrubber.setVehicleSummary({ count, live })
    }
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

  simulationDateString() {
    if (!this.simulationAt) return null
    const date = new Date(this.simulationAt)
    if (Number.isNaN(date.getTime())) return null
    const shifted = new Date(date.getTime() + (8 * 60 * 60 * 1000))
    const year = shifted.getUTCFullYear()
    const month = String(shifted.getUTCMonth() + 1).padStart(2, "0")
    const day = String(shifted.getUTCDate()).padStart(2, "0")
    return `${year}-${month}-${day}`
  }

  isNearLiveClock() {
    if (!this.simulationAt) return false
    const sim = Date.parse(this.simulationAt)
    if (!Number.isFinite(sim)) return false
    return Math.abs(sim - Date.now()) <= LIVE_OVERLAY_WINDOW_MS
  }

  async ensureScheduleSnapshots(routeIds) {
    const date = this.simulationDateString()
    if (!date) return

    const wanted = Array.from(new Set(routeIds)).filter(Boolean)
    const missing = wanted.filter((id) => this.scheduleSnapshots[id]?.date !== date)
    wanted.forEach((id) => {
      if (this.scheduleSnapshots[id] && this.scheduleSnapshots[id].date !== date) {
        delete this.scheduleSnapshots[id]
      }
    })
    if (missing.length === 0) return

    if (this.scheduleFetchController) this.scheduleFetchController.abort()
    this.scheduleFetchController = new AbortController()
    const { signal } = this.scheduleFetchController

    try {
      for (let index = 0; index < missing.length; index += SCHEDULE_FETCH_CHUNK) {
        const chunk = missing.slice(index, index + SCHEDULE_FETCH_CHUNK)
        const params = new URLSearchParams({ date })
        chunk.forEach((id) => params.append("route_ids[]", id))

        const response = await fetch(`/api/schedules?${params}`, { signal })
        if (!response.ok) return

        const data = await response.json()
        const loaded = new Set()
        ;(data.routes || []).forEach((route) => {
          this.scheduleSnapshots[route.route_id] = { date: data.date, ...route }
          loaded.add(route.route_id)
        })
        chunk.forEach((id) => {
          if (!loaded.has(id)) this.scheduleSnapshots[id] = { date, route_id: id, trips: [] }
        })
        this.scheduleDate = date
        this.refreshLocalFleet({ resync: true })
      }
    } catch (error) {
      if (error?.name === "AbortError") return
      console.warn("schedules fetch failed", error)
    }
  }

  buildLocalVehicles() {
    const atMin = this.minutesSinceMidnightFromIso(this.simulationAt)
    if (!Number.isFinite(atMin)) return []

    const vehicles = []
    this.visibleRouteLayerIds().forEach((routeId) => {
      const snap = this.scheduleSnapshots[routeId]
      if (!snap?.trips) return

      snap.trips.forEach((trip) => {
        const overlay = this.liveOverlayFor(trip, snap)
        const vehicle = {
          id: trip.id,
          soft_id: trip.id,
          train_number: trip.train_number,
          destination_name: trip.destination_name,
          label: this.isMetroSystemId(snap.system_id) ? trip.destination_name : trip.train_number,
          direction: trip.direction,
          trip_type: trip.trip_type,
          route_id: snap.route_id,
          system_id: snap.system_id,
          color: snap.color,
          path: trip.path,
          continues_as: trip.continues_as,
          position_source: overlay?.position_source || "timetable",
          delay_seconds: overlay?.delay_seconds || 0,
          delay_source: overlay?.delay_source || "none",
          lat: overlay?.lat,
          lng: overlay?.lng
        }
        if (!this.placeVehicleOnPath(vehicle, atMin)) return
        vehicles.push(vehicle)
      })
    })

    return vehicles
  }

  isMetroSystemId(systemId) {
    return String(systemId || "").includes("metro") || String(systemId || "").endsWith("_lrt")
  }

  liveOverlayFor(trip, snap) {
    const byId = this.liveOverlayByKey[String(trip.id)]
    if (byId) return byId
    const train = String(trip.train_number || "").trim()
    if (!train) return null
    return this.liveOverlayByKey[`${snap.route_id}:${train}`] || this.liveOverlayByKey[train] || null
  }

  mergeLiveOverlay(vehicles, liveMeta = {}) {
    const next = {}
    vehicles.forEach((vehicle) => {
      const overlay = {
        delay_seconds: Number(vehicle.delay_seconds) || 0,
        delay_source: vehicle.delay_source || "none",
        position_source: vehicle.position_source,
        lat: vehicle.lat,
        lng: vehicle.lng
      }
      if (vehicle.id) next[String(vehicle.id)] = overlay
      if (vehicle.train_number) {
        next[`${vehicle.route_id}:${vehicle.train_number}`] = overlay
        next[String(vehicle.train_number)] = overlay
      }
    })
    this.liveOverlayByKey = liveMeta.applied === false ? {} : next
  }

  advanceExistingMarkers(vehicles) {
    const byId = {}
    vehicles.forEach((vehicle) => {
      byId[String(vehicle.id)] = vehicle
    })

    Object.entries(this.vehicleMarkersById).forEach(([id, marker]) => {
      const vehicle = byId[id]
      if (!vehicle) return
      marker._vehicleData = vehicle
      const latlng = this.interpolateVehiclePosition(vehicle)
      this.setVehicleMarkerVisible(marker, Boolean(latlng))
      if (latlng) this.moveVehicleMarker(marker, latlng)
    })
  }

  easedHopProgress(linear, vehicle) {
    const kind = motionKind(vehicle?.system_id, vehicle?.trip_type)
    return easedProgress(linear, kind)
  }

  ensureRouteChainage(routeId) {
    if (this.routeChainage[routeId]) return this.routeChainage[routeId]
    const line = longestTrackLine(this.vehicleTracksFor(routeId))
    const chainage = buildChainage(line)
    if (chainage) this.routeChainage[routeId] = chainage
    return chainage
  }

  stationKmOnRoute(routeId, ref) {
    const chainage = this.ensureRouteChainage(routeId)
    const coord = this.stationCoordForRef(ref, routeId)
    if (!chainage || !coord) return null
    return nearestDistance(chainage, coord[1], coord[0])
  }

  chainagePointForVehicle(vehicle, progress) {
    let fromKm = Number(vehicle.from_km)
    let toKm = Number(vehicle.to_km)
    if (!Number.isFinite(fromKm)) fromKm = this.stationKmOnRoute(vehicle.route_id, vehicle.from_station_ref)
    if (!Number.isFinite(toKm)) toKm = this.stationKmOnRoute(vehicle.route_id, vehicle.to_station_ref)
    if (!Number.isFinite(fromKm) || !Number.isFinite(toKm)) return null

    const chainage = this.ensureRouteChainage(vehicle.route_id)
    if (!chainage) return null
    const km = fromKm + ((toKm - fromKm) * Math.max(0, Math.min(1, progress)))
    return pointAtDistance(chainage, km)
  }

  followJourneyKm(vehicle) {
    const path = Array.isArray(vehicle?.path) ? vehicle.path : []
    const start = Number(path[0]?.km)
    let now = Number.isFinite(vehicle.from_km) && Number.isFinite(vehicle.to_km)
      ? vehicle.from_km + ((vehicle.to_km - vehicle.from_km) * (vehicle.progress || 0))
      : Number.NaN
    if (!Number.isFinite(start) || !Number.isFinite(now)) {
      const startKm = this.stationKmOnRoute(vehicle.route_id, path[0]?.r)
      const nowKm = this.stationKmOnRoute(vehicle.route_id, vehicle.from_station_ref)
      if (!Number.isFinite(startKm) || !Number.isFinite(nowKm)) return null
      return Math.abs(nowKm - startKm)
    }
    return Math.abs(now - start)
  }

  followSpeedKmh(vehicle) {
    if (vehicle?.status === "stopped") return 0
    const hopKm = Number.isFinite(vehicle.from_km) && Number.isFinite(vehicle.to_km)
      ? Math.abs(vehicle.to_km - vehicle.from_km)
      : null
    const hopMinutes = this.wrappedMinuteSpan(
      Number(vehicle.motion_departure_minutes),
      Number(vehicle.motion_arrival_minutes)
    )
    if (!(hopKm > 0) || !(hopMinutes > 0)) return null
    return speedKmh(vehicle.linear_progress ?? vehicle.progress ?? 0, {
      kind: motionKind(vehicle.system_id, vehicle.trip_type),
      hopKm,
      hopMinutes
    })
  }

  redrawVehicleCanvas(vehicles = null) {
    if (!this.vehicleCanvas) return
    const list = vehicles || this.buildLocalVehicles()
    const entries = list.map((vehicle) => {
      const latlng = this.interpolateVehiclePosition(vehicle)
      if (!latlng) return null
      return {
        id: vehicle.id,
        latlng,
        color: this.normalizeHexColor(vehicle.color) || "#64748b",
        label: this.vehicleLabel(vehicle),
        vehicle
      }
    }).filter(Boolean)
    this.vehicleCanvas.setVehicles(entries, {
      followedId: this.followedMarker?._vehicleData?.id || this.followedVehicleKey
    })
  }

  handleCanvasVehicleSelect(entry) {
    const marker = this.vehicleMarkersById[String(entry.id)]
    if (marker) {
      marker.openPopup()
      return
    }
    if (entry.vehicle) this.startFollowingVehicle(entry.vehicle)
  }

  warmFollowTiles() {
    if (!this.map || !this.tileLayer || this.simulationSpeed < 10) return
    const latlng = this.followLastLatLng || this.followedMarker?.getLatLng()
    if (!latlng) return

    const now = performance.now()
    if (this._tileWarmAt && now - this._tileWarmAt < 450) return
    this._tileWarmAt = now

    const zoom = Math.round(this.map.getZoom() ?? 12)
    const template = this.tileLayer._url
    if (!template) return

    const projected = this.map.project(latlng, zoom)
    const vehicle = this.followedMarker?._vehicleData
    const bearing = vehicle ? this.vehicleBearingDegrees(vehicle, latlng) : 0
    const rad = (bearing * Math.PI) / 180
    const ahead = 280
    const centers = [
      [ Math.floor(projected.x / 256), Math.floor(projected.y / 256) ],
      [
        Math.floor((projected.x + Math.sin(rad) * ahead) / 256),
        Math.floor((projected.y - Math.cos(rad) * ahead) / 256)
      ]
    ]

    const L = window.L
    centers.forEach(([ cx, cy ]) => {
      for (let dx = -1; dx <= 1; dx += 1) {
        for (let dy = -1; dy <= 1; dy += 1) {
          const url = L.Util.template(template, {
            s: [ "a", "b", "c" ][(Math.abs(cx + dx) + Math.abs(cy + dy)) % 3],
            x: cx + dx,
            y: cy + dy,
            z: zoom,
            r: ""
          })
          const img = new Image()
          img.referrerPolicy = "no-referrer"
          img.src = url
        }
      }
    })
  }

  stationBoardRows(ref, routeId = null, windowMinutes = STATION_BOARD_MINUTES) {
    const atMin = this.minutesSinceMidnightFromIso(this.simulationAt)
    if (!Number.isFinite(atMin) || !ref) return []

    const tokens = this.transferStationRefs(ref)
    const rows = []
    const routeIds = routeId ? [ routeId ] : this.visibleRouteLayerIds()

    routeIds.forEach((id) => {
      const snap = this.scheduleSnapshots[id]
      snap?.trips?.forEach((trip) => {
        (trip.path || []).forEach((stop) => {
          if (stop.t) return
          const stopTokens = this.transferStationRefs(stop.r)
          if (!tokens.some((token) => stopTokens.includes(token) || token === stop.r || stop.r === ref)) return
          const arrival = Number(stop.a)
          if (!Number.isFinite(arrival)) return
          let wait = arrival - atMin
          if (wait < -120) wait += 1440
          if (wait < -0.5 || wait > windowMinutes) return
          rows.push({
            id: trip.id,
            train_number: trip.train_number,
            destination_name: trip.destination_name,
            route_id: id,
            wait,
            arrival,
            name: stop.n
          })
        })
      })
    })

    return rows.sort((a, b) => a.wait - b.wait).slice(0, 12)
  }

  stationBoardHtml(ref, routeId, stationName) {
    const rows = this.stationBoardRows(ref, routeId)
    if (rows.length === 0) {
      return `<div class="station-board"><div class="station-board__empty">${this.escapeHtml(this.t("explore.board_empty"))}</div></div>`
    }

    const items = rows.map((row) => {
      const mins = Math.max(0, Math.round(row.wait))
      const label = row.train_number || row.destination_name || row.route_id
      const dest = row.destination_name ? ` → ${row.destination_name}` : ""
      return `<button type="button" class="station-board__row" data-follow-trip="${this.escapeHtml(row.id)}" data-follow-train="${this.escapeHtml(row.train_number || "")}" data-follow-route="${this.escapeHtml(row.route_id)}">
        <span>${this.escapeHtml(label)}${this.escapeHtml(dest)}</span>
        <span>${mins}${this.escapeHtml(this.t("explore.minutes_short"))}</span>
      </button>`
    }).join("")

    return `<div class="station-board">
      <div class="station-board__title">${this.escapeHtml(this.t("explore.board_title", { name: stationName || ref }))}</div>
      ${items}
    </div>`
  }

  bindStationBoardActions(root) {
    if (!root) return
    root.querySelectorAll("[data-follow-trip]").forEach((button) => {
      if (button._bound) return
      button._bound = true
      button.addEventListener("click", (event) => {
        event.preventDefault()
        event.stopPropagation()
        this.followTripFromBoard(button.dataset.followTrip, button.dataset.followTrain, button.dataset.followRoute)
      })
    })
  }

  openStationBoard({ routeId, ref, name }) {
    this.ensureExploreUi()
    const panel = this.stationBoardEl
    if (!panel) return
    panel.hidden = false
    panel.innerHTML = `
      <div class="map-float-panel__head">
        <strong>${this.escapeHtml(name || ref || "")}</strong>
        <button type="button" class="map-float-panel__close" data-station-board-close>&times;</button>
      </div>
      ${this.stationBoardHtml(ref, null, name)}
    `
    panel.querySelector("[data-station-board-close]")?.addEventListener("click", () => {
      panel.hidden = true
    })
    this.bindStationBoardActions(panel)
  }

  followTripFromBoard(tripId, trainNumber, routeId) {
    const marker = Object.values(this.vehicleMarkersById).find((item) => String(item._vehicleData?.id) === String(tripId))
    if (marker) {
      this.startFollowingVehicle(marker._vehicleData, marker)
      return
    }

    this.pendingFollowTripId = tripId || null
    this.pendingFollowTrainNumber = trainNumber || null
    if (routeId && !this.layerVisible[routeId]) {
      this.setRouteLayersVisible([ routeId ], true, { fitBounds: false })
    }
    this.tryAdoptPendingFollowVehicle()
  }

  readShareParams() {
    const params = new URLSearchParams(window.location.search)
    const routes = String(params.get("routes") || "").split(",").map((id) => id.trim()).filter(Boolean)
    const lat = Number.parseFloat(params.get("lat"))
    const lng = Number.parseFloat(params.get("lng"))
    const z = Number.parseFloat(params.get("z"))
    return {
      at: params.get("at"),
      lat: Number.isFinite(lat) ? lat : null,
      lng: Number.isFinite(lng) ? lng : null,
      z: Number.isFinite(z) ? z : null,
      routes,
      follow: params.get("follow")
    }
  }

  async applyShareParams() {
    const share = this.pendingShare
    if (!share) return

    this.applyingShare = true
    try {
      if (share.at) this.setScrubberAt(share.at)
      if (Number.isFinite(share.lat) && Number.isFinite(share.lng) && this.map) {
        this.map.setView([ share.lat, share.lng ], share.z || this.map.getZoom(), { animate: false })
      }
      if (share.follow) {
        this.pendingFollowTripId = share.follow.startsWith("trip:") ? share.follow : null
        this.pendingFollowTrainNumber = share.follow
        this.tryAdoptPendingFollowVehicle()
      }
    } finally {
      this.applyingShare = false
    }
  }

  setScrubberAt(iso) {
    const scrubberEl = document.querySelector("[data-controller~='time-scrubber']")
    const scrubber = scrubberEl
      ? this.application.getControllerForElementAndIdentifier(scrubberEl, "time-scrubber")
      : null
    if (scrubber?.setFromIso) {
      scrubber.setFromIso(iso)
      return
    }
    this.simulationAt = iso
  }

  scheduleShareUrlUpdate() {
    if (this.applyingShare || this.booting) return
    if (this.shareTimer) clearTimeout(this.shareTimer)
    this.shareTimer = setTimeout(() => this.writeShareUrl(), 400)
  }

  writeShareUrl() {
    if (!this.map || this.applyingShare) return
    const center = this.map.getCenter()
    const params = new URLSearchParams(window.location.search)
    if (this.simulationAt) params.set("at", this.simulationAt)
    if (center) {
      params.set("lat", center.lat.toFixed(5))
      params.set("lng", center.lng.toFixed(5))
    }
    params.set("z", String(Math.round((this.map.getZoom() ?? 11) * 10) / 10))
    const routes = this.visibleRouteLayerIds()
    if (routes.length) params.set("routes", routes.join(","))
    else params.delete("routes")
    if (this.followedTrainNumber || this.followedVehicleKey) {
      params.set("follow", this.followedTrainNumber || this.followedVehicleKey)
    } else {
      params.delete("follow")
    }

    const next = `${window.location.pathname}?${params.toString()}`
    const current = `${window.location.pathname}${window.location.search}`
    if (next !== current) window.history.replaceState({}, "", next)
  }

  async loadCrossings() {
    try {
      const data = await this.fetchGeoJSON("/geojson/level_crossings.json")
      this.crossingFeatures = Array.isArray(data?.features) ? data.features : []
    } catch (_error) {
      this.crossingFeatures = []
    }
  }

  toggleCrossings() {
    this.crossingsVisible = !this.crossingsVisible
    this.syncCrossingLayer()
    this.syncExploreToolState()
  }

  syncCrossingLayer() {
    if (!this.map || !this.crossingGroup) return
    this.crossingGroup.clearLayers()
    if (!this.crossingsVisible) {
      if (this.map.hasLayer(this.crossingGroup)) this.map.removeLayer(this.crossingGroup)
      return
    }

    const L = window.L
    this.crossingFeatures.forEach((feature) => {
      const coords = feature.geometry?.coordinates
      if (!Array.isArray(coords) || coords.length < 2) return
      const marker = L.circleMarker([ coords[1], coords[0] ], {
        radius: 5,
        color: "#b45309",
        weight: 1.5,
        fillColor: "#fbbf24",
        fillOpacity: 0.9
      })
      marker.bindPopup(() => this.crossingPopupHtml(feature), { maxWidth: 300 })
      marker.on("popupopen", () => this.bindStationBoardActions(marker.getPopup()?.getElement()))
      this.crossingGroup.addLayer(marker)
    })
    if (!this.map.hasLayer(this.crossingGroup)) this.crossingGroup.addTo(this.map)
  }

  crossingPopupHtml(feature) {
    const name = feature.properties?.name || this.t("explore.crossing")
    const d = Number(feature.properties?.d)
    const routeId = feature.properties?.route_id
    const rows = this.crossingPassRows(routeId, d)
    const list = rows.length
      ? rows.map((row) => {
        const mins = Math.max(0, Math.round(row.wait))
        return `<button type="button" class="station-board__row" data-follow-trip="${this.escapeHtml(row.id)}" data-follow-train="${this.escapeHtml(row.train_number || "")}" data-follow-route="${this.escapeHtml(row.route_id)}">
          <span>${this.escapeHtml(row.train_number || row.destination_name || "")}</span>
          <span>${mins}${this.escapeHtml(this.t("explore.minutes_short"))}</span>
        </button>`
      }).join("")
      : `<div class="station-board__empty">${this.escapeHtml(this.t("explore.board_empty"))}</div>`

    return `<div class="station-board">
      <div class="station-board__title">${this.escapeHtml(name)}</div>
      <div class="station-board__note">${this.escapeHtml(this.t("explore.timetable_estimate"))}</div>
      ${list}
    </div>`
  }

  crossingPassRows(routeId, distanceKm, windowMinutes = STATION_BOARD_MINUTES) {
    const atMin = this.minutesSinceMidnightFromIso(this.simulationAt)
    if (!Number.isFinite(atMin) || !Number.isFinite(distanceKm)) return []

    const snap = this.scheduleSnapshots[routeId]
    if (!snap) return []

    const rows = []
    snap.trips?.forEach((trip) => {
      const path = trip.path || []
      for (let i = 0; i < path.length - 1; i += 1) {
        const a = Number(path[i].km)
        const b = Number(path[i + 1].km)
        if (!Number.isFinite(a) || !Number.isFinite(b)) continue
        const lo = Math.min(a, b)
        const hi = Math.max(a, b)
        if (distanceKm < lo || distanceKm > hi || hi === lo) continue
        const frac = (distanceKm - a) / (b - a)
        const dep = Number(path[i].d)
        const arr = Number(path[i + 1].a)
        if (!Number.isFinite(dep) || !Number.isFinite(arr)) continue
        let span = arr - dep
        if (span < -720) span += 1440
        const pass = dep + (span * frac)
        let wait = pass - atMin
        if (wait < -120) wait += 1440
        if (wait < -0.5 || wait > windowMinutes) continue
        rows.push({
          id: trip.id,
          train_number: trip.train_number,
          destination_name: trip.destination_name,
          route_id: routeId,
          wait
        })
      }
    })
    return rows.sort((a, b) => a.wait - b.wait).slice(0, 10)
  }

  togglePinMode() {
    this.pinMode = !this.pinMode
    this.syncExploreToolState()
    if (this.pinMode) {
      this.map?.getContainer()?.classList.add("map--pin-mode")
      if (!this._onMapPinClick) {
        this._onMapPinClick = (event) => this.dropNearbyPin(event.latlng)
        this.map?.on("click", this._onMapPinClick)
      }
    } else {
      this.map?.getContainer()?.classList.remove("map--pin-mode")
      if (this._onMapPinClick) {
        this.map?.off("click", this._onMapPinClick)
        this._onMapPinClick = null
      }
    }
  }

  dropNearbyPin(latlng) {
    if (!latlng) return
    const pin = {
      id: `pin-${Date.now()}`,
      lat: latlng.lat,
      lng: latlng.lng,
      saved: false
    }
    this.nearbyPins.push(pin)
    this.renderNearbyPins()
    this.openNearbyPanel(pin)
    this.pinMode = false
    this.map?.getContainer()?.classList.remove("map--pin-mode")
    if (this._onMapPinClick) {
      this.map?.off("click", this._onMapPinClick)
      this._onMapPinClick = null
    }
    this.syncExploreToolState()
  }

  renderNearbyPins() {
    if (!this.nearbyPinGroup) return
    const L = window.L
    this.nearbyPinGroup.clearLayers()
    this.nearbyPins.forEach((pin) => {
      const marker = L.marker([ pin.lat, pin.lng ], { pane: "vehicles" })
      marker.on("click", () => this.openNearbyPanel(pin))
      this.nearbyPinGroup.addLayer(marker)
    })
  }

  nearbyTrainRows(latlng) {
    const atMin = this.minutesSinceMidnightFromIso(this.simulationAt)
    if (!Number.isFinite(atMin) || !latlng) return []

    const rows = []
    this.visibleRouteLayerIds().forEach((routeId) => {
      const chainage = this.ensureRouteChainage(routeId)
      if (!chainage) return
      const d = nearestDistance(chainage, latlng.lng, latlng.lat)
      if (!Number.isFinite(d)) return
      const point = pointAtDistance(chainage, d)
      if (!point) return
      const distM = this.haversineMeters(latlng.lat, latlng.lng, point.lat, point.lng)
      if (distM > NEARBY_RADIUS_M) return
      this.crossingPassRows(routeId, d).forEach((row) => {
        rows.push({ ...row, meters: Math.round(distM) })
      })
    })

    return rows.sort((a, b) => a.wait - b.wait).slice(0, 12)
  }

  openNearbyPanel(pin) {
    this.ensureExploreUi()
    const panel = this.nearbyPanelEl
    if (!panel) return
    const rows = this.nearbyTrainRows({ lat: pin.lat, lng: pin.lng })
    const list = rows.length
      ? rows.map((row) => {
        const mins = Math.max(0, Math.round(row.wait))
        return `<button type="button" class="station-board__row" data-follow-trip="${this.escapeHtml(row.id)}" data-follow-train="${this.escapeHtml(row.train_number || "")}" data-follow-route="${this.escapeHtml(row.route_id)}">
          <span>${this.escapeHtml(row.train_number || row.destination_name || "")} · ${row.meters}m</span>
          <span>${mins}${this.escapeHtml(this.t("explore.minutes_short"))}</span>
        </button>`
      }).join("")
      : `<div class="station-board__empty">${this.escapeHtml(this.t("explore.board_empty"))}</div>`

    panel.hidden = false
    panel.innerHTML = `
      <div class="map-float-panel__head">
        <strong>${this.escapeHtml(this.t("explore.nearby_title"))}</strong>
        <button type="button" class="map-float-panel__close" data-nearby-close>&times;</button>
      </div>
      <div class="station-board__note">${this.escapeHtml(this.t("explore.timetable_estimate"))}</div>
      ${list}
      <button type="button" class="map-float-panel__action" data-nearby-save>${this.escapeHtml(pin.saved ? this.t("explore.pin_saved") : this.t("explore.save_pin"))}</button>
    `
    panel.querySelector("[data-nearby-close]")?.addEventListener("click", () => { panel.hidden = true })
    panel.querySelector("[data-nearby-save]")?.addEventListener("click", (event) => {
      pin.saved = true
      this.persistPins()
      event.currentTarget.textContent = this.t("explore.pin_saved")
    })
    this.bindStationBoardActions(panel)
  }

  persistPins() {
    try {
      const saved = this.nearbyPins.filter((pin) => pin.saved).map((pin) => ({ lat: pin.lat, lng: pin.lng }))
      window.localStorage?.setItem(NEARBY_PIN_STORAGE_KEY, JSON.stringify(saved))
    } catch (_error) {
      // ignore
    }
  }

  loadStoredPins() {
    try {
      const raw = window.localStorage?.getItem(NEARBY_PIN_STORAGE_KEY)
      const parsed = raw ? JSON.parse(raw) : []
      this.nearbyPins = Array.isArray(parsed)
        ? parsed.map((pin, index) => ({ id: `saved-${index}`, lat: pin.lat, lng: pin.lng, saved: true }))
        : []
      this.renderNearbyPins()
    } catch (_error) {
      this.nearbyPins = []
    }
  }

  async copyShareUrl() {
    this.writeShareUrl()
    const url = window.location.href
    try {
      await navigator.clipboard?.writeText(url)
    } catch (_error) {
      window.prompt(this.t("explore.share"), url)
    }
    this.flashExploreNotice(this.t("explore.share_copied"))
  }

  async loadAlerts() {
    try {
      const response = await fetch("/api/alerts")
      if (!response.ok) return
      const data = await response.json()
      this.renderAlertBanner(Array.isArray(data.alerts) ? data.alerts : [])
    } catch (_error) {
      // optional feed
    }
  }

  renderAlertBanner(alerts) {
    this.ensureExploreUi()
    const el = this.alertBannerEl
    if (!el) return
    const visible = alerts.filter((alert) => alert?.id && !this.dismissedAlertIds.has(String(alert.id)))
    if (visible.length === 0) {
      el.hidden = true
      el.replaceChildren()
      return
    }

    el.hidden = false
    el.innerHTML = visible.map((alert) => `
      <div class="map-alert-banner__item" data-alert-id="${this.escapeHtml(alert.id)}">
        <span>${this.escapeHtml(alert.title || alert.message || "")}</span>
        <button type="button" data-alert-dismiss="${this.escapeHtml(alert.id)}">&times;</button>
      </div>
    `).join("")
    el.querySelectorAll("[data-alert-dismiss]").forEach((button) => {
      button.addEventListener("click", () => {
        this.dismissedAlertIds.add(String(button.dataset.alertDismiss))
        this.renderAlertBanner(alerts)
      })
    })
  }

  rideStamps() {
    try {
      const raw = window.localStorage?.getItem(RIDE_STAMP_STORAGE_KEY)
      const parsed = raw ? JSON.parse(raw) : []
      return Array.isArray(parsed) ? parsed : []
    } catch (_error) {
      return []
    }
  }

  recordRideStamp(vehicle) {
    if (!vehicle) return
    const stamps = this.rideStamps()
    const date = this.simulationDateString()
    const entry = {
      date,
      route_id: vehicle.route_id,
      train_number: vehicle.train_number || vehicle.label,
      destination_name: vehicle.destination_name,
      km: this.followJourneyKm(vehicle)
    }
    const key = `${entry.date}:${entry.route_id}:${entry.train_number}`
    if (stamps.some((stamp) => `${stamp.date}:${stamp.route_id}:${stamp.train_number}` === key)) return
    stamps.unshift(entry)
    try {
      window.localStorage?.setItem(RIDE_STAMP_STORAGE_KEY, JSON.stringify(stamps.slice(0, 80)))
    } catch (_error) {
      // ignore
    }
  }

  randomHopTrain() {
    const vehicles = this.buildLocalVehicles()
    if (vehicles.length === 0) return
    const pick = vehicles[Math.floor(Math.random() * vehicles.length)]
    const marker = this.vehicleMarkersById[String(pick.id)]
    this.startFollowingVehicle(pick, marker || null)
  }

  toggleRelaxMode() {
    this.exploreRelax = !this.exploreRelax
    document.body.classList.toggle("map-relax-mode", this.exploreRelax)
    try {
      window.localStorage?.setItem(RELAX_MODE_STORAGE_KEY, this.exploreRelax ? "1" : "0")
    } catch (_error) {
      // ignore
    }
    if (this.exploreRelax && this.basemapStyle !== "carto") {
      this.setBasemapStyle({ target: { value: "carto" } })
    }
    this.syncExploreToolState()
  }

  restoreRelaxMode() {
    try {
      this.exploreRelax = window.localStorage?.getItem(RELAX_MODE_STORAGE_KEY) === "1"
    } catch (_error) {
      this.exploreRelax = false
    }
    document.body.classList.toggle("map-relax-mode", this.exploreRelax)
  }

  toggleExplorePanel() {
    this.ensureExploreUi()
    if (!this.explorePanelEl) return
    this.explorePanelEl.hidden = !this.explorePanelEl.hidden
    if (!this.explorePanelEl.hidden) this.renderExplorePanel()
  }

  renderExplorePanel() {
    const stamps = this.rideStamps()
    const items = stamps.slice(0, 12).map((stamp) => {
      const km = Number.isFinite(stamp.km) ? ` · ${Number(stamp.km).toFixed(1)}km` : ""
      return `<li>${this.escapeHtml(stamp.date || "")} · ${this.escapeHtml(stamp.train_number || stamp.route_id || "")}${this.escapeHtml(km)}</li>`
    }).join("") || `<li>${this.escapeHtml(this.t("explore.stamps_empty"))}</li>`

    this.explorePanelEl.innerHTML = `
      <div class="map-float-panel__head">
        <strong>${this.escapeHtml(this.t("explore.title"))}</strong>
        <button type="button" class="map-float-panel__close" data-explore-close>&times;</button>
      </div>
      <p class="station-board__note">${this.escapeHtml(this.t("explore.stamps_count", { count: stamps.length }))}</p>
      <ul class="explore-stamp-list">${items}</ul>
      <div class="map-float-panel__actions">
        <button type="button" class="map-float-panel__action" data-explore-random>${this.escapeHtml(this.t("explore.random_train"))}</button>
        <button type="button" class="map-float-panel__action" data-explore-relax>${this.escapeHtml(this.exploreRelax ? this.t("explore.relax_off") : this.t("explore.relax_on"))}</button>
      </div>
    `
    this.explorePanelEl.querySelector("[data-explore-close]")?.addEventListener("click", () => {
      this.explorePanelEl.hidden = true
    })
    this.explorePanelEl.querySelector("[data-explore-random]")?.addEventListener("click", () => this.randomHopTrain())
    this.explorePanelEl.querySelector("[data-explore-relax]")?.addEventListener("click", () => {
      this.toggleRelaxMode()
      this.renderExplorePanel()
    })
  }

  flashExploreNotice(message) {
    this.ensureExploreUi()
    if (!this.exploreToolsEl) return
    const note = this.exploreToolsEl.querySelector(".map-explore-tools__note")
    if (!note) return
    note.textContent = message
    note.hidden = false
    clearTimeout(this._exploreNoteTimer)
    this._exploreNoteTimer = setTimeout(() => { note.hidden = true }, 1800)
  }

  syncExploreToolState() {
    if (!this.exploreToolsEl) return
    this.exploreToolsEl.querySelector("[data-tool='pin']")?.classList.toggle("is-active", this.pinMode)
    this.exploreToolsEl.querySelector("[data-tool='crossings']")?.classList.toggle("is-active", this.crossingsVisible)
    this.exploreToolsEl.querySelector("[data-tool='relax']")?.classList.toggle("is-active", this.exploreRelax)
  }

  ensureExploreUi() {
    if (this.exploreToolsEl) return
    const host = this.hasMapTarget
      ? (this.mapTarget.parentElement || this.mapTarget)
      : this.element

    const banner = document.createElement("div")
    banner.className = "map-alert-banner"
    banner.hidden = true
    host.appendChild(banner)
    this.alertBannerEl = banner

    const tools = document.createElement("div")
    tools.className = "map-explore-tools"
    tools.innerHTML = `
      <button type="button" data-tool="share">${this.escapeHtml(this.t("explore.share"))}</button>
      <button type="button" data-tool="pin">${this.escapeHtml(this.t("explore.pin"))}</button>
      <button type="button" data-tool="crossings">${this.escapeHtml(this.t("explore.crossings"))}</button>
      <button type="button" data-tool="explore">${this.escapeHtml(this.t("explore.title"))}</button>
      <span class="map-explore-tools__note" hidden></span>
    `
    tools.addEventListener("click", (event) => {
      const button = event.target.closest("[data-tool]")
      if (!button) return
      const tool = button.dataset.tool
      if (tool === "share") this.copyShareUrl()
      if (tool === "pin") this.togglePinMode()
      if (tool === "crossings") this.toggleCrossings()
      if (tool === "explore") this.toggleExplorePanel()
    })
    host.appendChild(tools)
    this.exploreToolsEl = tools

    const stationBoard = document.createElement("div")
    stationBoard.className = "map-float-panel map-station-board-panel"
    stationBoard.hidden = true
    host.appendChild(stationBoard)
    this.stationBoardEl = stationBoard

    const nearby = document.createElement("div")
    nearby.className = "map-float-panel map-nearby-panel"
    nearby.hidden = true
    host.appendChild(nearby)
    this.nearbyPanelEl = nearby

    const explore = document.createElement("div")
    explore.className = "map-float-panel map-explore-panel"
    explore.hidden = true
    host.appendChild(explore)
    this.explorePanelEl = explore
  }
}

