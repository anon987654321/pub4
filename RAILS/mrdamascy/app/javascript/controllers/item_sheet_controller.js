import { Controller } from "@hotwired/stimulus"
import { formatOre } from "money"

// Item sheet (§8): qty stepper, option chip logic (max two sauces at once),
// and live recalculation of the sticky "Legg i kurv · pris" total. Extras are
// priced via data-price-ore on each option; sauces/toppings are free.
export default class extends Controller {
  static targets = ["quantity", "price", "submit", "option", "sauceNotice"]
  static values = { base: Number, template: String, max: { type: Number, default: 20 }, sauceLimit: String }

  connect() {
    this.recalc()
  }

  increase() {
    this.setQuantity(this.quantity() + 1)
  }

  decrease() {
    this.setQuantity(this.quantity() - 1)
  }

  recalc() {
    const extrasOre = this.optionTargets
      .filter((input) => input.checked)
      .reduce((sum, input) => sum + (Number(input.dataset.priceOre) || 0), 0)
    const totalOre = Math.max(0, (this.baseValue || 0) + extrasOre) * this.quantity()

    if (this.hasPriceTarget) {
      this.priceTarget.textContent = this.formatOre(totalOre)
    }
    if (this.hasSubmitTarget && this.templateValue) {
      this.submitTarget.value = this.templateValue.replace("%{price}", this.formatOre(totalOre))
    }
    this.enforceSauceLimit()
  }

  // private

  quantity() {
    const parsed = Number.parseInt(this.quantityTarget.value, 10)
    return Number.isNaN(parsed) || parsed < 1 ? 1 : parsed
  }

  setQuantity(next) {
    this.quantityTarget.value = Math.min(this.maxValue, Math.max(1, next))
    this.recalc()
  }

  // Toum plus tarator plus chili is a trio too far — cap free sauces at two.
  // Reaching the cap is said in the polite notice, once, so a screen-reader
  // user hears why the other chips went quiet.
  enforceSauceLimit() {
    const sauces = this.optionTargets.filter((input) => input.dataset.kind === "sauce")
    const full = sauces.filter((input) => input.checked).length >= 2
    sauces.forEach((input) => {
      input.disabled = full && !input.checked
    })

    if (this.hasSauceNoticeTarget && full !== this.sauceLimitReached) {
      this.sauceNoticeTarget.textContent = full ? this.sauceLimitValue : ""
    }
    this.sauceLimitReached = full
  }

  formatOre(ore) {
    return formatOre(ore)
  }
}
