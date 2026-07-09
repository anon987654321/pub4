import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    max: Number,
    warningAt: { type: Number, default: 0.8 },
    dangerAt: { type: Number, default: 0.95 }
  }

  connect() {
    this.boundUpdate = this.update.bind(this)
    this.element.addEventListener("input", this.boundUpdate)
    this.element.addEventListener("change", this.boundUpdate)
    this.update()
  }

  disconnect() {
    this.element.removeEventListener("input", this.boundUpdate)
    this.element.removeEventListener("change", this.boundUpdate)
  }

  update() {
    const counter = this.counterElement()
    if (!counter || !this.hasMaxValue) return

    const length = (this.element.value || "").length
    const remaining = this.maxValue - length
    const usedRatio = this.maxValue > 0 ? length / this.maxValue : 0

    counter.textContent = `${remaining} left`
    counter.style.color = usedRatio >= this.dangerAtValue ? "#dc2626" : usedRatio >= this.warningAtValue ? "#d97706" : ""
  }

  counterElement() {
    return this.element.nextElementSibling?.matches?.("[data-char-counter-target='counter'], .char-counter") ?
      this.element.nextElementSibling :
      this.element.parentElement?.querySelector("[data-char-counter-target='counter'], .char-counter")
  }
}
