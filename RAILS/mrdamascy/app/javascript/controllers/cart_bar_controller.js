import { Controller } from "@hotwired/stimulus"
import { formatOre } from "money"

// Pay-bar (§8): pulses after a cart form submission succeeds (a refused
// add or any other form leaves it still) and refreshes count/total when the
// server broadcasts cart:changed (detail: { count, total_ore }). The primary
// refresh path is the Turbo Stream re-render of #cart_bar itself.
export default class extends Controller {
  static values = { cartPath: String }

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

  pulse(event) {
    if (!this.cartFormSucceeded(event)) return

    this.element.classList.add("cart-bar-pulse")
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.element.classList.remove("cart-bar-pulse"), 600)
  }

  cartFormSucceeded(event) {
    const form = event?.target
    if (!event?.detail?.success || !form?.action || !this.cartPathValue) return false

    return new URL(form.action, window.location.href).pathname.startsWith(this.cartPathValue)
  }

  changed(event) {
    const detail = event.detail || {}
    const count = this.element.querySelector("[data-cart-bar-count]")
    const total = this.element.querySelector("[data-cart-bar-total]")
    if (count && detail.count != null) count.textContent = detail.count
    if (total && detail.total_ore != null) {
      total.textContent = formatOre(detail.total_ore)
    }
  }
}
