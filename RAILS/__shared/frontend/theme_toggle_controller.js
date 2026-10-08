import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { storageKey: { type: String, default: "pub4-theme" } }

  connect() {
    const theme = this.#storedTheme()
    if (theme) {
      this.#applyTheme(theme)
      if ("checked" in this.element) this.element.checked = theme === "light"
    }
  }

  persist() {
    const theme = this.element.checked ? "light" : "dark"
    this.#applyTheme(theme)
    try {
      localStorage.setItem(this.storageKeyValue, theme)
    } catch (_error) {
      // Ignore quota or privacy-mode failures.
    }
  }

  #storedTheme() {
    try {
      const value = localStorage.getItem(this.storageKeyValue)
      return value === "light" || value === "dark" ? value : null
    } catch (_error) {
      return null
    }
  }

  #applyTheme(theme) {
    document.documentElement.dataset.theme = theme
  }
}
