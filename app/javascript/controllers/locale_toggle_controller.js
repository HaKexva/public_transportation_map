import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  toggle() {
    const current = document.documentElement.dataset.locale || "zh-TW"
    const next = current === "en" ? "zh-TW" : "en"

    document.cookie = `locale=${encodeURIComponent(next)};path=/;max-age=31536000;SameSite=Lax`
    window.location.reload()
  }
}
