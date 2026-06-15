import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { mode: { type: String, default: "single" } }

  connect() {
    if (window.flatpickr) {
      this.picker = window.flatpickr(this.element, { mode: this.modeValue })
    } else {
      this.element.type = "date"
    }
  }

  disconnect() {
    this.picker?.destroy()
  }
}