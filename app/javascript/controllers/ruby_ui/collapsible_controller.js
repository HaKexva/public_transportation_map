import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["content", "trigger"]
  static values = {
    open: {
      type: Boolean,
      default: false,
    },
  }

  connect() {
    this.openValue ? this.open() : this.close()
  }

  toggle() {
    this.openValue = !this.openValue
  }

  openValueChanged(isOpen) {
    if (isOpen) {
      this.open()
    } else {
      this.close()
    }
  }

  open() {
    if (!this.hasContentTarget) return

    this.contentTarget.classList.remove("hidden")
    this.syncTriggerState(true)
  }

  close() {
    if (!this.hasContentTarget) return

    this.contentTarget.classList.add("hidden")
    this.syncTriggerState(false)
  }

  syncTriggerState(isOpen = this.openValue) {
    if (!this.hasTriggerTarget) return

    this.triggerTargets.forEach((trigger) => {
      trigger.setAttribute("aria-expanded", isOpen.toString())
    })
  }
}
