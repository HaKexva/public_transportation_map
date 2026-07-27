import { Controller } from "@hotwired/stimulus"

const STORAGE_KEY_POS = "mapTimeScrubberPos"
const STORAGE_KEY_SPEED = "mapTimeScrubberSpeed"
const DEBOUNCE_MS = 150
const PLAY_SPEEDS = [ 1, 2, 5, 10, 30, 60 ]
const DEFAULT_PLAY_SPEED = 1
const MIN_TICK_MS = 16

export default class extends Controller {
  static targets = [
    "panel",
    "dateLabel",
    "timeLabel",
    "slider",
    "playButton",
    "speedSelect",
    "hint",
    "vehicleCount",
    "statusOnTime",
    "statusDelayed",
    "statusEarly"
  ]

  connect() {
    this.at = new Date()
    this.playing = false
    this.playTimer = null
    this.emitTimer = null
    this.playSpeed = this.loadPlaySpeed()
    this.draggingPanel = false
    this.dragOffsetX = 0
    this.dragOffsetY = 0

    this.onPointerMove = this.handlePanelPointerMove.bind(this)
    this.onPointerUp = this.stopPanelDrag.bind(this)

    this.restorePosition()
    this.syncSpeedSelect()
    this.syncLabels()
    this.syncSlider()
    this.emitTime({ immediate: true })
  }

  disconnect() {
    this.stopPlayback()
    this.clearEmitTimer()
    this.stopPanelDrag()
  }

  // --- Panel drag (header only) ---

  startPanelDrag(event) {
    if (event.button !== undefined && event.button !== 0) return
    if (event.target.closest("button, input, select, a, label")) return

    event.preventDefault()
    this.draggingPanel = true
    this.panelTarget.classList.add("time-scrubber--dragging")

    const rect = this.panelTarget.getBoundingClientRect()
    this.dragOffsetX = event.clientX - rect.left
    this.dragOffsetY = event.clientY - rect.top

    window.addEventListener("pointermove", this.onPointerMove)
    window.addEventListener("pointerup", this.onPointerUp)
    window.addEventListener("pointercancel", this.onPointerUp)
  }

  handlePanelPointerMove(event) {
    if (!this.draggingPanel) return

    const parent = this.panelTarget.offsetParent || document.body
    const parentRect = parent.getBoundingClientRect()
    const panelRect = this.panelTarget.getBoundingClientRect()

    let left = event.clientX - parentRect.left - this.dragOffsetX
    let top = event.clientY - parentRect.top - this.dragOffsetY

    left = Math.max(8, Math.min(left, parentRect.width - panelRect.width - 8))
    top = Math.max(8, Math.min(top, parentRect.height - panelRect.height - 8))

    this.panelTarget.style.left = `${left}px`
    this.panelTarget.style.top = `${top}px`
    this.panelTarget.style.right = "auto"
    this.panelTarget.style.bottom = "auto"
  }

  stopPanelDrag() {
    if (!this.draggingPanel) return

    this.draggingPanel = false
    this.panelTarget.classList.remove("time-scrubber--dragging")
    window.removeEventListener("pointermove", this.onPointerMove)
    window.removeEventListener("pointerup", this.onPointerUp)
    window.removeEventListener("pointercancel", this.onPointerUp)
    this.persistPosition()
  }

  restorePosition() {
    try {
      const raw = localStorage.getItem(STORAGE_KEY_POS)
      if (!raw) return

      const pos = JSON.parse(raw)
      if (!Number.isFinite(pos?.left) || !Number.isFinite(pos?.top)) return

      this.panelTarget.style.left = `${pos.left}px`
      this.panelTarget.style.top = `${pos.top}px`
      this.panelTarget.style.right = "auto"
      this.panelTarget.style.bottom = "auto"
    } catch (_error) {
      // ignore
    }
  }

  persistPosition() {
    try {
      const left = Number.parseFloat(this.panelTarget.style.left)
      const top = Number.parseFloat(this.panelTarget.style.top)
      if (!Number.isFinite(left) || !Number.isFinite(top)) return

      localStorage.setItem(STORAGE_KEY_POS, JSON.stringify({ left, top }))
    } catch (_error) {
      // ignore
    }
  }

  // --- Time controls ---

  scrub(event) {
    const minutes = Number.parseInt(event.target.value, 10)
    if (!Number.isFinite(minutes)) return

    const next = new Date(this.at)
    next.setHours(Math.floor(minutes / 60), minutes % 60, this.at.getSeconds(), 0)
    this.at = next
    this.syncLabels()
    this.emitTime()
  }

  jumpToNow() {
    this.at = new Date()
    this.syncLabels()
    this.syncSlider()
    this.emitTime({ immediate: true })
  }

  shiftDay(event) {
    const delta = Number.parseInt(event.currentTarget.dataset.delta || "0", 10)
    if (!delta) return

    const next = new Date(this.at)
    next.setDate(next.getDate() + delta)
    this.at = next
    this.syncLabels()
    this.emitTime({ immediate: true })
  }

  changeSpeed(event) {
    const speed = Number.parseInt(event.target.value, 10)
    this.playSpeed = PLAY_SPEEDS.includes(speed) ? speed : DEFAULT_PLAY_SPEED
    this.persistPlaySpeed()

    if (this.playing) {
      this.stopPlaybackTimer()
      this.startPlaybackTimer()
    }
  }

  togglePlay() {
    if (this.playing) {
      this.stopPlayback()
    } else {
      this.startPlayback()
    }
  }

  startPlayback() {
    this.playing = true
    this.syncPlayButton()
    this.startPlaybackTimer()
  }

  startPlaybackTimer() {
    this.stopPlaybackTimer()

    // Advance one simulation second per tick; speed shortens the real-time interval.
    const tickMs = Math.max(MIN_TICK_MS, Math.round(1000 / this.playSpeed))

    this.playTimer = window.setInterval(() => {
      this.at = new Date(this.at.getTime() + 1000)
      this.syncLabels()
      this.syncSlider()
      // During play, refresh promptly so the map follows each second.
      this.emitTime({ immediate: this.playSpeed <= 5 })
    }, tickMs)
  }

  stopPlayback() {
    this.playing = false
    this.syncPlayButton()
    this.stopPlaybackTimer()
  }

  stopPlaybackTimer() {
    if (this.playTimer) {
      clearInterval(this.playTimer)
      this.playTimer = null
    }
  }

  syncPlayButton() {
    if (!this.hasPlayButtonTarget) return

    this.playButtonTarget.textContent = this.playing
      ? this.t("time_scrubber.pause")
      : this.t("time_scrubber.play")
    this.playButtonTarget.setAttribute("aria-pressed", this.playing ? "true" : "false")
  }

  syncSpeedSelect() {
    if (!this.hasSpeedSelectTarget) return

    this.speedSelectTarget.value = String(this.playSpeed)
  }

  loadPlaySpeed() {
    try {
      const stored = Number.parseInt(localStorage.getItem(STORAGE_KEY_SPEED), 10)
      if (PLAY_SPEEDS.includes(stored)) return stored
    } catch (_error) {
      // ignore
    }

    return DEFAULT_PLAY_SPEED
  }

  persistPlaySpeed() {
    try {
      localStorage.setItem(STORAGE_KEY_SPEED, String(this.playSpeed))
    } catch (_error) {
      // ignore
    }
  }

  syncLabels() {
    if (this.hasDateLabelTarget) {
      this.dateLabelTarget.textContent = this.formatDate(this.at)
    }
    if (this.hasTimeLabelTarget) {
      this.timeLabelTarget.textContent = this.formatTime(this.at)
    }
  }

  syncSlider() {
    if (!this.hasSliderTarget) return

    this.sliderTarget.value = String(this.at.getHours() * 60 + this.at.getMinutes())
  }

  emitTime({ immediate = false } = {}) {
    const dispatch = () => {
      window.dispatchEvent(new CustomEvent("map:simulation-time", {
        detail: { at: this.at.toISOString() }
      }))
    }

    this.clearEmitTimer()
    if (immediate) {
      dispatch()
      return
    }

    this.emitTimer = window.setTimeout(dispatch, DEBOUNCE_MS)
  }

  clearEmitTimer() {
    if (this.emitTimer) {
      clearTimeout(this.emitTimer)
      this.emitTimer = null
    }
  }

  setVehicleSummary({ count = 0, onTime = 0, delayed = 0, early = 0 } = {}) {
    if (this.hasVehicleCountTarget) {
      this.vehicleCountTarget.textContent = this.t("time_scrubber.vehicle_count", { count })
    }
    if (this.hasStatusOnTimeTarget) this.statusOnTimeTarget.textContent = String(onTime)
    if (this.hasStatusDelayedTarget) this.statusDelayedTarget.textContent = String(delayed)
    if (this.hasStatusEarlyTarget) this.statusEarlyTarget.textContent = String(early)

    if (this.hasHintTarget) {
      this.hintTarget.hidden = count > 0
    }
  }

  formatDate(date) {
    try {
      return new Intl.DateTimeFormat(this.localeTag(), {
        year: "numeric",
        month: "2-digit",
        day: "2-digit",
        weekday: "short"
      }).format(date)
    } catch (_error) {
      return date.toISOString().slice(0, 10)
    }
  }

  formatTime(date) {
    const hh = String(date.getHours()).padStart(2, "0")
    const mm = String(date.getMinutes()).padStart(2, "0")
    const ss = String(date.getSeconds()).padStart(2, "0")
    return `${hh}:${mm}:${ss}`
  }

  localeTag() {
    const locale = document.documentElement.dataset.locale || document.documentElement.lang || "zh-TW"
    return locale === "zh-TW" || locale.startsWith("zh") ? "zh-TW" : "en"
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
}
