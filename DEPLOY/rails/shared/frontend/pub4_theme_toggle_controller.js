import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { storageKey: { type: String, default: "pub4-theme" } }

  connect() {
    try {
      this.element.checked = localStorage.getItem(this.storageKeyValue) === "light"
    } catch (_error) {
      // localStorage may be unavailable in restricted contexts.
    }
  }

  persist() {
    try {
      localStorage.setItem(this.storageKeyValue, this.element.checked ? "light" : "dark")
    } catch (_error) {
      // Ignore quota or privacy-mode failures.
    }
  }
}