import { Controller } from "@hotwired/stimulus"

const STORAGE_KEY_POS = "mapTimeScrubberPos"
const STORAGE_KEY_SPEED = "mapTimeScrubberSpeed"
const STORAGE_KEY_EXPANDED = "mapTimeScrubberExpanded"
const DEBOUNCE_MS = 150
const PLAY_SPEEDS = [ 1, 2, 5, 10, 30, 60 ]
const DEFAULT_PLAY_SPEED = 1
const CLOCK_TZ = "Asia/Taipei"
const TAIPEI_OFFSET_MS = 8 * 60 * 60 * 1000

export default class extends Controller {
  static targets = [
    "panel",
    "dateLabel",
    "timeLabel",
    "slider",
    "playButton",
    "speedSelect",
    "expandButton",
    "details",
    "hint",
    "vehicleCount",
    "badge"
  ]

  connect() {
    this.at = new Date()
    this.playing = false
    this.playTimer = null
    this.emitTimer = null
    this.playSpeed = this.loadPlaySpeed()
    this.expanded = this.loadExpanded()
    this.draggingPanel = false
    this.dragOffsetX = 0
    this.dragOffsetY = 0

    this.onPointerMove = this.handlePanelPointerMove.bind(this)
    this.onPointerUp = this.stopPanelDrag.bind(this)

    this.restorePosition()
    this.syncExpanded()
    this.syncSpeedSelect()
    this.syncLabels()
    this.syncSlider()
    this.emitTime({ immediate: true })
    // Map may connect after us — re-emit once controllers settle.
    this._bootEmitTimer = setTimeout(() => this.emitTime({ immediate: true }), 400)
  }

  disconnect() {
    this.stopPlayback()
    this.clearEmitTimer()
    this.stopPanelDrag()
    if (this._bootEmitTimer) {
      clearTimeout(this._bootEmitTimer)
      this._bootEmitTimer = null
    }
  }

  // --- Panel drag (compact bar only) ---

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

  // --- Expand / collapse ---

  toggleExpanded() {
    this.expanded = !this.expanded
    this.persistExpanded()
    this.syncExpanded()
  }

  syncExpanded() {
    this.panelTarget.classList.toggle("time-scrubber--collapsed", !this.expanded)
    this.panelTarget.classList.toggle("time-scrubber--expanded", this.expanded)

    if (this.hasExpandButtonTarget) {
      this.expandButtonTarget.textContent = this.expanded
        ? this.t("time_scrubber.collapse")
        : this.t("time_scrubber.expand")
      this.expandButtonTarget.setAttribute("aria-expanded", this.expanded ? "true" : "false")
      this.expandButtonTarget.setAttribute(
        "aria-label",
        this.expanded ? this.t("time_scrubber.collapse") : this.t("time_scrubber.expand")
      )
    }
  }

  loadExpanded() {
    try {
      const raw = localStorage.getItem(STORAGE_KEY_EXPANDED)
      if (raw === "1" || raw === "true") return true
      if (raw === "0" || raw === "false") return false
    } catch (_error) {
      // ignore
    }

    return false
  }

  persistExpanded() {
    try {
      localStorage.setItem(STORAGE_KEY_EXPANDED, this.expanded ? "1" : "0")
    } catch (_error) {
      // ignore
    }
  }

  // --- Time controls ---

  scrub(event) {
    const minutes = Number.parseInt(event.target.value, 10)
    if (!Number.isFinite(minutes)) return

    this.at = this.setTaipeiClock(this.at, {
      hours: Math.floor(minutes / 60),
      minutes: minutes % 60,
      seconds: 0,
      milliseconds: 0
    })
    this.syncLabels()
    // Scrubbing must move vehicles with the clock (even when not playing).
    this.emitTime({ immediate: true })
  }

  jumpToNow() {
    this.at = new Date()
    this.syncLabels()
    this.syncSlider()
    this.emitTime({ immediate: true })
  }

  setFromIso(iso) {
    const date = new Date(iso)
    if (Number.isNaN(date.getTime())) return

    this.at = date
    this.syncLabels()
    this.syncSlider()
    this.emitTime({ immediate: true })
  }

  shiftDay(event) {
    const delta = Number.parseInt(event.currentTarget.dataset.delta || "0", 10)
    if (!delta) return

    this.at = new Date(this.at.getTime() + delta * 24 * 60 * 60 * 1000)
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

    window.dispatchEvent(new CustomEvent("map:simulation-speed", {
      detail: { speed: this.playSpeed, playing: this.playing }
    }))
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
    window.dispatchEvent(new CustomEvent("map:simulation-speed", {
      detail: { speed: this.playSpeed, playing: true }
    }))
  }

  startPlaybackTimer() {
    this.stopPlaybackTimer()

    // Smooth clock: advance by real elapsed * speed using rAF (not 1s jumps).
    this._playLastTs = null
    this._lastEmitTs = 0
    const tick = (ts) => {
      if (!this.playing) return

      if (this._playLastTs == null) this._playLastTs = ts
      const deltaMs = Math.min(100, ts - this._playLastTs)
      this._playLastTs = ts

      this.at = new Date(this.at.getTime() + deltaMs * this.playSpeed)
      this.syncLabels()
      this.syncSlider()

      // Emit often enough for map/API sync, but not every paint.
      if (!this._lastEmitTs || ts - this._lastEmitTs >= 50) {
        this._lastEmitTs = ts
        this.emitTime({ immediate: true })
      }

      this.playTimer = window.requestAnimationFrame(tick)
    }

    this.playTimer = window.requestAnimationFrame(tick)
  }

  stopPlayback() {
    this.playing = false
    this.syncPlayButton()
    this.stopPlaybackTimer()
    window.dispatchEvent(new CustomEvent("map:simulation-speed", {
      detail: { speed: this.playSpeed, playing: false }
    }))
  }

  stopPlaybackTimer() {
    if (this.playTimer) {
      window.cancelAnimationFrame(this.playTimer)
      this.playTimer = null
    }
    this._playLastTs = null
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

    const parts = this.taipeiParts(this.at)
    this.sliderTarget.value = String(parts.hours * 60 + parts.minutes)
  }

  emitTime({ immediate = false } = {}) {
    const dispatch = () => {
      window.dispatchEvent(new CustomEvent("map:simulation-time", {
        detail: {
          at: this.at.toISOString(),
          speed: this.playSpeed,
          playing: this.playing,
          immediate
        }
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

  setVehicleSummary({ count = 0, live = false } = {}) {
    if (this.hasVehicleCountTarget) {
      this.vehicleCountTarget.textContent = this.t("time_scrubber.vehicle_count", { count })
    }

    if (this.hasHintTarget) {
      this.hintTarget.hidden = count > 0
    }

    if (this.hasBadgeTarget) {
      this.badgeTarget.textContent = live
        ? this.t("time_scrubber.live_badge")
        : this.t("time_scrubber.synthetic_badge")
      this.badgeTarget.classList.toggle("time-scrubber__badge--live", Boolean(live))
    }
  }

  formatDate(date) {
    try {
      return new Intl.DateTimeFormat(this.localeTag(), {
        timeZone: CLOCK_TZ,
        month: "2-digit",
        day: "2-digit",
        weekday: "short"
      }).format(date)
    } catch (_error) {
      return date.toISOString().slice(5, 10)
    }
  }

  formatTime(date) {
    const parts = this.taipeiParts(date)
    const hh = String(parts.hours).padStart(2, "0")
    const mm = String(parts.minutes).padStart(2, "0")
    const ss = String(parts.seconds).padStart(2, "0")
    return `${hh}:${mm}:${ss}`
  }

  // Simulation clock is always Asia/Taipei (UTC+8, no DST).
  taipeiParts(date) {
    const shifted = new Date(date.getTime() + TAIPEI_OFFSET_MS)
    return {
      year: shifted.getUTCFullYear(),
      month: shifted.getUTCMonth(),
      day: shifted.getUTCDate(),
      hours: shifted.getUTCHours(),
      minutes: shifted.getUTCMinutes(),
      seconds: shifted.getUTCSeconds()
    }
  }

  setTaipeiClock(baseDate, { hours, minutes, seconds = 0, milliseconds = 0 }) {
    const parts = this.taipeiParts(baseDate)
    return new Date(Date.UTC(
      parts.year,
      parts.month,
      parts.day,
      hours,
      minutes,
      seconds,
      milliseconds
    ) - TAIPEI_OFFSET_MS)
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
