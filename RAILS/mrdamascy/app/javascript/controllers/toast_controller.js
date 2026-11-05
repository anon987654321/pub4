import { Controller } from "@hotwired/stimulus"

// Flash toast (§8): dismiss button + auto-dismiss after the delay value. An
// alert (persist) stays until the reader closes it. The default is the
// family's one toast duration, 4000 ms, the delay shared/_toast and the
// shared action controller give the shared toast, under the same
// data-toast-delay-value name.
export default class extends Controller {
  static values = { persist: Boolean, delay: { type: Number, default: 4000 } }

  connect() {
    if (this.persistValue) return
    this.timer = setTimeout(() => this.dismiss(), this.delayValue)
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
