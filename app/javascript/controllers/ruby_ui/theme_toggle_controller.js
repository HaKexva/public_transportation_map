import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "lightButton", "darkButton" ]

  connect() {
    this.setTheme()
  }

  setTheme() {
    if (localStorage.theme === "dark" || (!("theme" in localStorage) && window.matchMedia("(prefers-color-scheme: dark)").matches)) {
      document.documentElement.classList.add("dark")
      document.documentElement.classList.remove("light")
    } else {
      document.documentElement.classList.remove("dark")
      document.documentElement.classList.add("light")
    }

    this.updateButtons()
  }

  setLightTheme() {
    localStorage.theme = "light"
    this.setTheme()
  }

  setDarkTheme() {
    localStorage.theme = "dark"
    this.setTheme()
  }

  updateButtons() {
    const isDark = document.documentElement.classList.contains("dark")

    if (this.hasLightButtonTarget) {
      this.lightButtonTarget.setAttribute("aria-pressed", String(!isDark))
    }

    if (this.hasDarkButtonTarget) {
      this.darkButtonTarget.setAttribute("aria-pressed", String(isDark))
    }
  }
}
