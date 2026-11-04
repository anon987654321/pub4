import { Controller } from "@hotwired/stimulus"

// Flash toast (§8): dismiss button + auto-dismiss after 3.5 seconds. An
// alert (persist) stays until the reader closes it.
export default class extends Controller {
  static values = { persist: Boolean }

  connect() {
    if (this.persistValue) return
    this.timer = setTimeout(() => this.dismiss(), 3500)
  }

  disconnect() {
    clearTimeout(this.timer)
  }

  dismiss() {
    if (this.element.dataset.dismissed) return
    this.element.dataset.dismissed = "true"
    this.element.classList.add("toast-out")
    setTimeout(() => this.element.remove(), 200)
  }
}
