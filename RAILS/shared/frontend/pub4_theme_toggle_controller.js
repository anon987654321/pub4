import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { storageKey: { type: String, default: "pub4-theme" } }

  connect() {
    try {
      const stored = localStorage.getItem(this.storageKeyValue)
      if (stored === "light") {
        this.element.checked = true
        document.documentElement.dataset.theme = "light"
      } else if (stored === "dark") {
        this.element.checked = false
        document.documentElement.dataset.theme = "dark"
      }
    } catch (_error) {
      // localStorage may be unavailable in restricted contexts.
    }
  }

  persist() {
    const theme = this.element.checked ? "light" : "dark"
    try {
      localStorage.setItem(this.storageKeyValue, theme)
    } catch (_error) {
      // Ignore quota or privacy-mode failures.
    }
    document.documentElement.dataset.theme = theme
  }
}
