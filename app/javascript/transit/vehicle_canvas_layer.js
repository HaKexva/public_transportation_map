function leaflet() {
  return window.L
}

export class VehicleCanvasLayer {
  constructor() {
    this._map = null
    this._canvas = null
    this._ctx = null
    this._vehicles = []
    this._followedId = null
    this._onReset = () => this._reset()
    this._onMapClick = (event) => this._handleMapClick(event)
    this.onSelect = null
  }

  addTo(map) {
    this._map = map
    const pane = map.getPane("vehicles") || map.getPanes().overlayPane
    const L = leaflet()
    this._canvas = L.DomUtil.create("canvas", "vehicle-canvas-layer")
    this._canvas.style.position = "absolute"
    this._canvas.style.left = "0"
    this._canvas.style.top = "0"
    // Let route/stop clicks pass through; vehicle picks use the map click handler.
    this._canvas.style.pointerEvents = "none"
    this._canvas.style.zIndex = 1
    pane.appendChild(this._canvas)
    this._ctx = this._canvas.getContext("2d")
    map.on("move resize zoom viewreset zoomanim", this._onReset)
    map.on("click", this._onMapClick)
    this._reset()
    return this
  }

  remove() {
    if (!this._map) return
    this._map.off("move resize zoom viewreset zoomanim", this._onReset)
    this._map.off("click", this._onMapClick)
    if (this._canvas) this._canvas.remove()
    this._map = null
    this._canvas = null
    this._ctx = null
  }

  setVehicles(vehicles, { followedId = null } = {}) {
    this._vehicles = Array.isArray(vehicles) ? vehicles : []
    this._followedId = followedId
    this.redraw()
  }

  redraw() {
    if (!this._map || !this._ctx || !this._canvas) return

    const size = this._map.getSize()
    const dpr = window.devicePixelRatio || 1
    this._canvas.width = Math.round(size.x * dpr)
    this._canvas.height = Math.round(size.y * dpr)
    this._canvas.style.width = `${size.x}px`
    this._canvas.style.height = `${size.y}px`
    this._ctx.setTransform(dpr, 0, 0, dpr, 0, 0)
    this._ctx.clearRect(0, 0, size.x, size.y)

    const zoom = this._map.getZoom() ?? 12
    const showLabels = zoom >= 10
    const radius = zoom <= 8 ? 3.5 : zoom <= 11 ? 5 : 6

    this._vehicles.forEach((entry) => {
      const point = this._map.latLngToContainerPoint(entry.latlng)
      if (point.x < -20 || point.y < -20 || point.x > size.x + 20 || point.y > size.y + 20) return

      const followed = this._followedId && String(entry.id) === String(this._followedId)
      this._ctx.beginPath()
      this._ctx.fillStyle = entry.color || "#64748b"
      this._ctx.strokeStyle = followed ? "#f8fafc" : "rgba(15,23,42,0.45)"
      this._ctx.lineWidth = followed ? 2.4 : 1
      this._ctx.arc(point.x, point.y, followed ? radius + 1.5 : radius, 0, Math.PI * 2)
      this._ctx.fill()
      this._ctx.stroke()

      if (showLabels && entry.label) {
        this._ctx.font = followed ? "600 11px system-ui, sans-serif" : "600 10px system-ui, sans-serif"
        this._ctx.textAlign = "center"
        this._ctx.textBaseline = "bottom"
        const text = String(entry.label)
        const width = Math.min(this._ctx.measureText(text).width + 10, 92)
        const x = point.x
        const y = point.y - radius - 4
        this._ctx.fillStyle = "rgba(15,23,42,0.78)"
        this._ctx.beginPath()
        this._ctx.roundRect?.(x - width / 2, y - 14, width, 14, 4)
        if (!this._ctx.roundRect) {
          this._ctx.rect(x - width / 2, y - 14, width, 14)
        }
        this._ctx.fill()
        this._ctx.fillStyle = "#f8fafc"
        this._ctx.fillText(text, x, y - 2)
      }
    })
  }

  _reset() {
    if (!this._map || !this._canvas) return
    const topLeft = this._map.containerPointToLayerPoint([ 0, 0 ])
    leaflet().DomUtil.setPosition(this._canvas, topLeft)
    this.redraw()
  }

  entryAt(containerPoint, maxDistance = 22) {
    if (!this._map || !containerPoint) return null

    let best = null
    let bestDist = maxDistance

    this._vehicles.forEach((entry) => {
      const projected = this._map.latLngToContainerPoint(entry.latlng)
      const dist = projected.distanceTo(containerPoint)
      if (dist < bestDist) {
        bestDist = dist
        best = entry
      }
    })

    return best
  }

  _handleMapClick(event) {
    if (!this._map || !this.onSelect) return

    // Prefer station/route interactive targets when the click landed on them.
    const target = event.originalEvent?.target
    if (target?.closest?.(".leaflet-interactive")) return

    const best = this.entryAt(event.containerPoint)
    if (!best) return

    const L = leaflet()
    if (L?.DomEvent) L.DomEvent.stop(event)
    this.onSelect(best)
  }
}
