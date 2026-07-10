import { Controller } from "@hotwired/stimulus"

const STORAGE_KEY_WIDTH = "mapSidebarWidthPx"
const DEFAULT_WIDTH_PX = 352
const MIN_WIDTH_PX = 240
const MAX_WIDTH_RATIO = 0.55
const MOBILE_MEDIA = "(max-width: 767px)"

export default class extends Controller {
  static targets = [ "sidebar", "resizer", "mapPane" ]

  connect() {
    this.dragging = false
    this.onPointerMove = this.handlePointerMove.bind(this)
    this.onPointerUp = this.stopDrag.bind(this)

    this.mediaQuery = window.matchMedia(MOBILE_MEDIA)
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
    if (this.isMobile() || this.isSidebarCollapsed()) return

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
    const width = event.clientX - bounds.left
    this.applyWidth(this.clampWidth(width))
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

  isMobile() {
    return this.mediaQuery?.matches ?? window.innerWidth <= 767
  }

  isSidebarCollapsed() {
    return this.element.classList.contains("map-split-layout--sidebar-collapsed")
  }

  syncLayoutMode() {
    this.element.classList.toggle("map-split-layout--mobile", this.isMobile())

    if (this.isMobile()) {
      this.element.classList.remove("map-split-layout--sidebar-collapsed")
      this.element.querySelector("[data-map-target=\"layersPanel\"]")
        ?.classList.remove("map-ui-panel--collapsed")
    } else {
      this.element.classList.remove("map-split-layout--layers-open")
      document.body.classList.remove("overflow-hidden")
    }
  }

  applyStoredSize() {
    if (this.isMobile() || this.isSidebarCollapsed()) {
      return
    }

    this.applyWidth(this.clampWidth(this.loadWidth()))
  }

  applyWidth(widthPx) {
    this.element.style.setProperty("--map-sidebar-width", `${widthPx}px`)
  }

  currentWidth() {
    const raw = getComputedStyle(this.element).getPropertyValue("--map-sidebar-width").trim()
    const parsed = Number.parseFloat(raw)

    return Number.isFinite(parsed) ? parsed : DEFAULT_WIDTH_PX
  }

  clampWidth(widthPx) {
    const max = Math.floor(this.element.getBoundingClientRect().width * MAX_WIDTH_RATIO)

    return Math.min(Math.max(widthPx, MIN_WIDTH_PX), Math.max(max, MIN_WIDTH_PX))
  }

  loadWidth() {
    return this.loadStoredSize(STORAGE_KEY_WIDTH, DEFAULT_WIDTH_PX, (value) => this.clampWidth(value))
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
    if (this.isMobile() || this.isSidebarCollapsed()) return

    try {
      localStorage.setItem(STORAGE_KEY_WIDTH, String(Math.round(this.currentWidth())))
    } catch (_error) {
      // ignore storage errors
    }
  }

  syncResizerAria() {
    const resizer = this.resizerTarget
    if (!resizer) return

    if (this.isMobile() || this.isSidebarCollapsed()) {
      resizer.setAttribute("aria-hidden", "true")
      resizer.setAttribute("tabindex", "-1")
      return
    }

    resizer.removeAttribute("aria-hidden")
    resizer.setAttribute("tabindex", "0")
    resizer.setAttribute("aria-orientation", "vertical")
    resizer.setAttribute("aria-label", "調整側欄與地圖寬度")
    resizer.setAttribute("aria-valuemin", String(MIN_WIDTH_PX))
    resizer.setAttribute("aria-valuemax", String(Math.round(window.innerWidth * MAX_WIDTH_RATIO)))
    resizer.setAttribute("aria-valuenow", String(Math.round(this.currentWidth())))
  }

  notifyMapResize() {
    window.dispatchEvent(new CustomEvent("map-split:resize"))
  }
}
