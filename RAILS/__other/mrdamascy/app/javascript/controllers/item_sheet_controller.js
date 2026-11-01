import { Controller } from "@hotwired/stimulus"

// Item sheet (§8): qty stepper, option chip logic (max two sauces at once),
// and live recalculation of the sticky "Legg i kurv · pris" total. Extras are
// priced via data-price-ore on each option; sauces/toppings are free.
export default class extends Controller {
  static targets = ["qty", "price", "submit", "option"]
  static values = { base: Number, template: String }

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
    const parsed = Number.parseInt(this.qtyTarget.value, 10)
    return Number.isNaN(parsed) || parsed < 1 ? 1 : parsed
  }

  setQuantity(next) {
    this.qtyTarget.value = Math.min(10, Math.max(1, next))
    this.recalc()
  }

  // Toum plus tarator plus chili is a trio too far — cap free sauces at two.
  enforceSauceLimit() {
    const sauces = this.optionTargets.filter((input) => input.dataset.kind === "sauce")
    const checked = sauces.filter((input) => input.checked)
    sauces.forEach((input) => {
      input.disabled = checked.length >= 2 && !input.checked
    })
  }

  formatOre(ore) {
    return `${Math.round(ore / 100)} kr`
  }
}
