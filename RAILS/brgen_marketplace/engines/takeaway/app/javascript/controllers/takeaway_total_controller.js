import { Controller } from "@hotwired/stimulus"

// The running subtotal on the takeaway order form, and how far it is from the
// kitchen's minimum, redrawn as quantities change. The minimum used to be a
// chip at the top and a below_minimum error after submitting; now the diner
// sees "kr 40 more to reach the minimum" while choosing. The server still
// checks the minimum; this only says it earlier.
export default class extends Controller {
  static targets = ["quantity", "subtotal", "shortfall"]
  static values = { minimumCents: Number, subtotalTemplate: String, shortfallTemplate: String, reachedText: String }

  connect() {
    this.update()
  }

  update() {
    const cents = this.quantityTargets.reduce((sum, input) => {
      const quantity = Math.max(0, parseInt(input.value, 10) || 0)
      return sum + quantity * (parseInt(input.dataset.priceCents, 10) || 0)
    }, 0)
    this.subtotalTarget.textContent = this.subtotalTemplateValue.replace("%{amount}", this.money(cents))
    if (!this.hasShortfallTarget) return

    const missing = this.minimumCentsValue - cents
    this.shortfallTarget.textContent = missing > 0
      ? this.shortfallTemplateValue.replace("%{amount}", this.money(missing))
      : this.reachedTextValue
  }

  // Shared::MoneyDisplay's NOK shape: "kr 1 250" or "kr 12,50".
  money(cents) {
    const whole = Math.floor(cents / 100)
    const part = cents % 100
    const grouped = String(whole).replace(/\B(?=(\d{3})+(?!\d))/g, " ")
    return `kr ${part === 0 ? grouped : `${grouped},${String(part).padStart(2, "0")}`}`
  }
}
