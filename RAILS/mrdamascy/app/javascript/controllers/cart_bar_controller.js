import { Controller } from "@hotwired/stimulus"

// Pay-bar (§8): pulses after quick-adds and refreshes count/total when the
// server broadcasts cart:changed (detail: { count, total_ore }). The primary
// refresh path is the Turbo Stream re-render of #cart_bar itself.
export default class extends Controller {
  connect() {
    this.onPulse = this.pulse.bind(this)
    this.onChanged = this.changed.bind(this)
    window.addEventListener("turbo:submit-end", this.onPulse)
    window.addEventListener("cart:changed", this.onChanged)
  }

  disconnect() {
    window.removeEventListener("turbo:submit-end", this.onPulse)
    window.removeEventListener("cart:changed", this.onChanged)
    clearTimeout(this.timer)
  }

  pulse() {
    this.element.classList.add("cart-bar-pulse")
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.element.classList.remove("cart-bar-pulse"), 600)
  }

  changed(event) {
    const detail = event.detail || {}
    const count = this.element.querySelector("[data-cart-bar-count]")
    const total = this.element.querySelector("[data-cart-bar-total]")
    if (count && detail.count != null) count.textContent = detail.count
    if (total && detail.total_ore != null) {
      total.textContent = `${Math.round(detail.total_ore / 100)} kr`
    }
  }
}
