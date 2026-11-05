import { Controller } from "@hotwired/stimulus"

// Three states, in this order: system (nothing stored, html carries no
// data-theme, so prefers-color-scheme decides), light, dark. A two-state
// switch could pick a theme but never give the choice back to the device.
const NEXT = { system: "light", light: "dark", dark: "system" }

export default class extends Controller {
  static values = {
    storageKey: { type: String, default: "pub4-theme" },
    labels: { type: Object, default: {} },
  }

  connect() {
    const theme = this.#storedTheme()
    this.#applyTheme(theme)
    this.#label(theme)
  }

  cycle() {
    const theme = NEXT[this.#storedTheme()]
    this.#store(theme)
    this.#applyTheme(theme)
    this.#label(theme)
  }

  #storedTheme() {
    try {
      const value = localStorage.getItem(this.storageKeyValue)
      return value === "light" || value === "dark" ? value : "system"
    } catch (_error) {
      return "system"
    }
  }

  #store(theme) {
    try {
      if (theme === "system") localStorage.removeItem(this.storageKeyValue)
      else localStorage.setItem(this.storageKeyValue, theme)
    } catch (_error) {
      // Ignore quota or privacy-mode failures.
    }
  }

  #applyTheme(theme) {
    if (theme === "system") delete document.documentElement.dataset.theme
    else document.documentElement.dataset.theme = theme
  }

  #label(theme) {
    const label = this.labelsValue[theme]
    if (!label) return
    this.element.setAttribute("aria-label", label)
    this.element.title = label
  }
}
