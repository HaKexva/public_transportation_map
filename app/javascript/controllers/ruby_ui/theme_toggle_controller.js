import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "lightButton", "darkButton" ]

  connect() {
    this.onStorage = (event) => {
      if (event.key === "theme") this.applyTheme({ persist: false })
    }

    window.addEventListener("storage", this.onStorage)
    this.applyTheme({ persist: false })
  }

  disconnect() {
    window.removeEventListener("storage", this.onStorage)
  }

  toggle() {
    const isDark = document.documentElement.classList.contains("dark")
    this.applyTheme({ theme: isDark ? "light" : "dark" })
  }

  setLightTheme() {
    this.applyTheme({ theme: "light" })
  }

  setDarkTheme() {
    this.applyTheme({ theme: "dark" })
  }

  applyTheme({ theme = null, persist = true } = {}) {
    const root = document.documentElement
    let useDark

    if (theme === "dark") {
      useDark = true
    } else if (theme === "light") {
      useDark = false
    } else {
      const stored = localStorage.getItem("theme")
      const prefersDark = window.matchMedia("(prefers-color-scheme: dark)").matches
      useDark = stored === "dark" || (stored !== "light" && prefersDark)
    }

    root.classList.toggle("dark", useDark)
    root.classList.remove("light")

    if (persist) {
      localStorage.setItem("theme", useDark ? "dark" : "light")
    }

    this.updateButtons()
    window.dispatchEvent(new CustomEvent("theme:changed", { detail: { dark: useDark } }))
  }

  updateButtons() {
    const isDark = document.documentElement.classList.contains("dark")

    if (this.hasLightButtonTarget) {
      this.lightButtonTarget.setAttribute("aria-pressed", String(!isDark))
      // Light icon should be visible only in light mode.
      this.lightButtonTarget.classList.toggle("hidden", isDark)
    }

    if (this.hasDarkButtonTarget) {
      this.darkButtonTarget.setAttribute("aria-pressed", String(isDark))
      this.darkButtonTarget.classList.toggle("hidden", isDark)
    }
  }
}
