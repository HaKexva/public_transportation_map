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

const METRO_SYSTEM_IDS = [
  "taipei_metro",
  "new_taipei_metro",
  "taoyuan_metro",
  "taichung_metro",
  "kaohsiung_metro"
]

export default class extends Controller {
  static targets = [ "map", "layerCheckbox" ]

  connect() {
    if (this.map) return

    this.layerGroups = {}
    this.layerVisible = {}
    this.layerLoadGeneration = {}
    this.geoJSONCache = {}
    this.routesManifest = {}
    this.lineColorsByPrefix = {}
    this.routesByLineRef = {}
    this.routeTracksByRouteId = {}
    this.branchesByMain = {}
    this.outOfStationTransfers = []
    this.stationCoordinatesByKey = {}
    this.mapReady = false
    this.setLayerControlsDisabled(true)
    this.waitForLeaflet(0)
  }

  disconnect() {
    if (this.resizeHandler) window.removeEventListener("resize", this.resizeHandler)
    this.map?.remove()
    this.map = null
    this.mapReady = false
    this.layerGroups = {}
    this.layerVisible = {}
    this.layerLoadGeneration = {}
    this.geoJSONCache = {}
    this.routesManifest = {}
    this.lineColorsByPrefix = {}
    this.routesByLineRef = {}
    this.routeTracksByRouteId = {}
    this.branchesByMain = {}
    this.outOfStationTransfers = []
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

    L.tileLayer("https://{s}.basemaps.cartocdn.com/light_nolabels/{z}/{x}/{y}{r}.png", {
      subdomains: "abcd",
      maxZoom: 20,
      attribution: "&copy; OpenStreetMap &copy; CARTO"
    }).addTo(this.map)

    await Promise.all([ this.loadRoutesManifest(), this.loadOutOfStationTransfers() ])

    this.outOfStationTransferGroup = L.featureGroup().addTo(this.map)

    this.allLayerIds().forEach((layerId) => {
      this.layerGroups[layerId] = L.featureGroup()
      this.layerVisible[layerId] = false
      this.layerLoadGeneration[layerId] = 0
    })

    this.map.fitBounds(LEAFLET_BOUNDS)
    this.map.zoomControl.setPosition("topright")

    this.resizeHandler = () => this.map?.invalidateSize(true)
    requestAnimationFrame(this.resizeHandler)
    setTimeout(this.resizeHandler, 100)
    setTimeout(this.resizeHandler, 500)
    window.addEventListener("resize", this.resizeHandler)

    this.mapReady = true
    this.setLayerControlsDisabled(false)
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
      const response = await fetch("/geojson/out_of_station_transfers.json")
      if (!response.ok) throw new Error("out-of-station transfers missing")

      this.outOfStationTransfers = await response.json()
    } catch (error) {
      console.error("Failed to load out-of-station transfers", error)
      this.outOfStationTransfers = []
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

        if (!route.branch_of) colorsByPrefix[route.ref] = route.color
      })
    })

    return { colorsByPrefix, routesByLineRef }
  }

  async resetView() {
    if (!this.mapReady || !this.map) return

    await this.setAllMetroLayersVisible(true, { fitBounds: true })
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
      this.stationCoordinatesByKey[this.stationKey(routeId, ref)] = latlng
    })
  }

  stationKey(routeId, ref) {
    return `${routeId}:${ref}`
  }

  stationLatLng(routeId, ref) {
    return this.stationCoordinatesByKey[this.stationKey(routeId, ref)]
  }

  updateOutOfStationTransfers() {
    const L = window.L
    const group = this.outOfStationTransferGroup

    if (!group || !this.map) return

    group.clearLayers()

    this.outOfStationTransfers.forEach((transfer) => {
      if (!transfer.routes?.every((routeId) => this.layerVisible[routeId])) return

      const latlngs = transfer.endpoints
        .map((endpoint) => this.stationLatLng(endpoint.route_id, endpoint.ref))
        .filter(Boolean)

      if (latlngs.length < 2) return

      const line = L.polyline(latlngs, {
        color: "#525252",
        weight: 3,
        opacity: 0.85,
        dashArray: "8 10",
        lineCap: "round"
      })

      if (transfer.label) {
        line.bindPopup(`<strong>${transfer.label}</strong><br><span style="opacity:0.8">站外轉乘</span>`)
      }

      group.addLayer(line)
    })

    if (group.getLayers().length > 0 && !this.map.hasLayer(group)) {
      group.addTo(this.map)
    }

    if (group.getLayers().length === 0 && this.map.hasLayer(group)) {
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

    const loads = routes.map((route) => this.addRouteToGroup(route, layerId, generation))
    const results = await Promise.allSettled(loads)

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

    const color = route.color || LAYER_COLORS[layerId] || "#666666"
    const routeRef = route.ref

    this.cacheRouteTracks(route.id, data)
    this.indexStationCoordinates(route.id, data)

    const geoLayer = L.geoJSON(data, {
      style: (feature) => this.styleForFeature(feature, color),
      pointToLayer: (feature, latlng) => this.stationMarker(feature, latlng, color, routeRef),
      onEachFeature: (feature, layer) => this.bindFeaturePopup(feature, layer)
    })

    if (!this.isLayerGenerationCurrent(layerId, generation) || !this.layerVisible[layerId]) return

    group.addLayer(geoLayer)
  }

  styleForFeature(feature, color) {
    if (feature.geometry?.type !== "LineString" && feature.geometry?.type !== "MultiLineString") {
      return {}
    }

    return {
      color,
      weight: 5,
      opacity: 0.9,
      lineCap: "round",
      lineJoin: "round"
    }
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
      if (feature.properties?.feature_type !== "route") return

      const geometry = feature.geometry
      if (geometry?.type === "LineString") {
        lines.push(geometry.coordinates)
      } else if (geometry?.type === "MultiLineString") {
        geometry.coordinates.forEach((coordinates) => lines.push(coordinates))
      }
    })

    return lines
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

  stationMarker(feature, latlng, color, routeRef) {
    const L = window.L

    if (feature.properties?.feature_type !== "station") return L.marker(latlng)

    const stationRefs = this.transferStationRefs(feature.properties?.ref)

    if (stationRefs.length > 1) {
      const lineColors = stationRefs
        .map((stationRef) => this.colorForStationRef(stationRef) || feature.properties?.color || color)
        .slice(0, 2)

      const snapPrefix = this.linePrefixForStationRef(stationRefs[0]) || routeRef
      const position = this.snapToTracks(latlng, snapPrefix)

      return this.transferStationMarkerAt(position, lineColors)
    }

    const stationRef = stationRefs[0]
    const linePrefix = this.linePrefixForStationRef(stationRef) || routeRef
    const position = this.snapToTracks(latlng, linePrefix)
    const lineColor = feature.properties?.color || this.colorForStationRef(stationRef) || color

    return this.circleMarkerAt(position, lineColor)
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
    if (routes.length === 1) return routes[0].color

    const mainRoute = routes.find((route) => !route.branch_of)
    const branchRoute = routes.find((route) => route.branch_of)

    if (this.isBranchStationRef(stationRef, prefix)) {
      return branchRoute?.color || mainRoute?.color
    }

    return mainRoute?.color || routes[0].color
  }

  isBranchStationRef(stationRef, linePrefix) {
    if (stationRef.endsWith("A")) return true

    return false
  }

  circleMarkerAt(latlng, color) {
    const L = window.L

    return L.circleMarker(latlng, {
      radius: 8,
      fillColor: color,
      color: "#ffffff",
      weight: 2,
      opacity: 1,
      fillOpacity: 0.95
    })
  }

  bindFeaturePopup(feature, layer) {
    const name = feature.properties?.name
    if (!name) return

    const ref = feature.properties?.ref
    const line = feature.properties?.line
    const label = ref ? `${ref} ${name}` : name
    const subtitle = line ? `<br><span style="opacity:0.8">${line}</span>` : ""
    const popup = `<strong>${label}</strong>${subtitle}`

    layer.bindPopup(popup)
  }

  async fetchGeoJSON(url) {
    if (!this.geoJSONCache[url]) {
      this.geoJSONCache[url] = fetch(url).then((response) => {
        if (!response.ok) throw new Error(`Failed to load ${url}`)
        return response.json()
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
