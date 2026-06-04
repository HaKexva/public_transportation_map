import { Controller } from "@hotwired/stimulus"

const STORAGE_KEY_WIDTH = "mapSidebarWidthPx"
const STORAGE_KEY_HEIGHT = "mapSidebarHeightPx"
const DEFAULT_WIDTH_PX = 352
const DEFAULT_HEIGHT_PX = 320
const MIN_WIDTH_PX = 240
const MIN_HEIGHT_PX = 160
const MAX_WIDTH_RATIO = 0.55
const MAX_HEIGHT_RATIO = 0.55
const STACKED_MEDIA = "(max-width: 767px)"

export default class extends Controller {
  static targets = [ "sidebar", "resizer", "mapPane" ]

  connect() {
    this.dragging = false
    this.onPointerMove = this.handlePointerMove.bind(this)
    this.onPointerUp = this.stopDrag.bind(this)

    this.mediaQuery = window.matchMedia(STACKED_MEDIA)
    this.onLayoutModeChange = () => {
      this.applyStoredSize()
      this.syncLayoutMode()
      this.syncResizerAria()
      this.notifyMapResize()
    }

    this.mediaQuery.addEventListener("change", this.onLayoutModeChange)
    window.addEventListener("resize", this.onWindowResize = () => {
      this.applyStoredSize()
      this.syncLayoutMode()
      this.syncResizerAria()
      this.notifyMapResize()
    })

    this.applyStoredSize()
    this.syncLayoutMode()
    this.syncResizerAria()
    requestAnimationFrame(() => this.notifyMapResize())
  }

  disconnect() {
    this.mediaQuery?.removeEventListener("change", this.onLayoutModeChange)
    window.removeEventListener("resize", this.onWindowResize)
    this.stopDrag()
  }

  startDrag(event) {
    if (event.button !== undefined && event.button !== 0) return

    event.preventDefault()
    this.dragging = true
    this.element.classList.add("map-split-layout--dragging")
    this.resizerTarget.setPointerCapture?.(event.pointerId)

    window.addEventListener("pointermove", this.onPointerMove)
    window.addEventListener("pointerup", this.onPointerUp)
    window.addEventListener("pointercancel", this.onPointerUp)
  }

  handlePointerMove(event) {
    if (!this.dragging) return

    const bounds = this.element.getBoundingClientRect()

    if (this.isStacked()) {
      const height = event.clientY - bounds.top
      this.applyHeight(this.clampHeight(height))
    } else {
      const width = event.clientX - bounds.left
      this.applyWidth(this.clampWidth(width))
    }
  }

  stopDrag() {
    if (!this.dragging) return

    this.dragging = false
    this.element.classList.remove("map-split-layout--dragging")

    window.removeEventListener("pointermove", this.onPointerMove)
    window.removeEventListener("pointerup", this.onPointerUp)
    window.removeEventListener("pointercancel", this.onPointerUp)

    this.persistSize()
    this.notifyMapResize()
  }

  isStacked() {
    return this.mediaQuery?.matches ?? window.innerWidth <= 767
  }

  syncLayoutMode() {
    this.element.classList.toggle("map-split-layout--stacked", this.isStacked())
  }

  applyStoredSize() {
    if (this.isStacked()) {
      this.applyHeight(this.clampHeight(this.loadHeight()))
    } else {
      this.applyWidth(this.clampWidth(this.loadWidth()))
    }
  }

  applyWidth(widthPx) {
    this.element.style.setProperty("--map-sidebar-width", `${widthPx}px`)
  }

  applyHeight(heightPx) {
    this.element.style.setProperty("--map-sidebar-height", `${heightPx}px`)
  }

  currentWidth() {
    const raw = getComputedStyle(this.element).getPropertyValue("--map-sidebar-width").trim()
    const parsed = Number.parseFloat(raw)

    return Number.isFinite(parsed) ? parsed : DEFAULT_WIDTH_PX
  }

  currentHeight() {
    const raw = getComputedStyle(this.element).getPropertyValue("--map-sidebar-height").trim()
    const parsed = Number.parseFloat(raw)

    return Number.isFinite(parsed) ? parsed : DEFAULT_HEIGHT_PX
  }

  clampWidth(widthPx) {
    const max = Math.floor(this.element.getBoundingClientRect().width * MAX_WIDTH_RATIO)

    return Math.min(Math.max(widthPx, MIN_WIDTH_PX), Math.max(max, MIN_WIDTH_PX))
  }

  clampHeight(heightPx) {
    const max = Math.floor(this.element.getBoundingClientRect().height * MAX_HEIGHT_RATIO)

    return Math.min(Math.max(heightPx, MIN_HEIGHT_PX), Math.max(max, MIN_HEIGHT_PX))
  }

  loadWidth() {
    return this.loadStoredSize(STORAGE_KEY_WIDTH, DEFAULT_WIDTH_PX, (value) => this.clampWidth(value))
  }

  loadHeight() {
    return this.loadStoredSize(STORAGE_KEY_HEIGHT, DEFAULT_HEIGHT_PX, (value) => this.clampHeight(value))
  }

  loadStoredSize(key, fallback, clamp) {
    try {
      const stored = Number.parseInt(localStorage.getItem(key), 10)

      if (Number.isFinite(stored) && stored > 0) return clamp(stored)
    } catch (_error) {
      // ignore storage errors
    }

    return clamp(fallback)
  }

  persistSize() {
    try {
      if (this.isStacked()) {
        localStorage.setItem(STORAGE_KEY_HEIGHT, String(Math.round(this.currentHeight())))
      } else {
        localStorage.setItem(STORAGE_KEY_WIDTH, String(Math.round(this.currentWidth())))
      }
    } catch (_error) {
      // ignore storage errors
    }
  }

  syncResizerAria() {
    const resizer = this.resizerTarget
    if (!resizer) return

    if (this.isStacked()) {
      resizer.setAttribute("aria-orientation", "horizontal")
      resizer.setAttribute("aria-label", "調整路線列表與地圖高度")
      resizer.setAttribute("aria-valuemin", String(MIN_HEIGHT_PX))
      resizer.setAttribute("aria-valuemax", String(Math.round(window.innerHeight * MAX_HEIGHT_RATIO)))
      resizer.setAttribute("aria-valuenow", String(Math.round(this.currentHeight())))
    } else {
      resizer.setAttribute("aria-orientation", "vertical")
      resizer.setAttribute("aria-label", "調整側欄與地圖寬度")
      resizer.setAttribute("aria-valuemin", String(MIN_WIDTH_PX))
      resizer.setAttribute("aria-valuemax", String(Math.round(window.innerWidth * MAX_WIDTH_RATIO)))
      resizer.setAttribute("aria-valuenow", String(Math.round(this.currentWidth())))
    }
  }

  notifyMapResize() {
    window.dispatchEvent(new CustomEvent("map-split:resize"))
  }
}
