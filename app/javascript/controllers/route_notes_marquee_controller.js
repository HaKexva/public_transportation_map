import { Controller } from "@hotwired/stimulus"

// Horizontal ticker for route note badges when they overflow the row.
export default class extends Controller {
  static targets = ["track", "group"]

  connect() {
    this.ro = new ResizeObserver(() => this.refresh())
    this.ro.observe(this.element)
    requestAnimationFrame(() => this.refresh())
  }

  disconnect() {
    this.ro?.disconnect()
    this.ro = null
  }

  refresh() {
    if (!this.hasTrackTarget || !this.hasGroupTarget) return

    this.trackTarget.querySelectorAll("[data-marquee-clone]").forEach((node) => node.remove())
    this.element.classList.remove("is-overflowing")
    this.element.style.removeProperty("--route-notes-marquee-duration")

    const overflow = this.groupTarget.scrollWidth > this.element.clientWidth + 1
    if (!overflow) return

    const clone = this.groupTarget.cloneNode(true)
    clone.removeAttribute("data-route-notes-marquee-target")
    clone.dataset.marqueeClone = "1"
    clone.setAttribute("aria-hidden", "true")
    this.trackTarget.append(clone)

    // ~36px/s, clamped so short notes still linger and long ones don't crawl.
    const distance = this.groupTarget.scrollWidth
    const seconds = Math.min(28, Math.max(8, distance / 36))
    this.element.style.setProperty("--route-notes-marquee-duration", `${seconds.toFixed(1)}s`)
    this.element.classList.add("is-overflowing")
  }
}
