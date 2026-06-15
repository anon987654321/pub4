import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["indicator"]
  static values = { threshold: { type: Number, default: 60 } }

  connect() {
    this.startY = 0
    this.pulling = false
  }

  touchstart(event) {
    if (window.scrollY === 0) this.startY = event.touches[0].clientY
  }

  touchmove(event) {
    const delta = event.touches[0].clientY - this.startY
    if (delta > 20 && window.scrollY === 0) {
      this.pulling = true
      if (this.hasIndicatorTarget) this.indicatorTarget.style.transform = `translateY(${Math.min(delta, 80)}px)`
    }
  }

  touchend(event) {
    const delta = (event.changedTouches?.[0]?.clientY || 0) - this.startY
    if (this.pulling && delta >= this.thresholdValue) {
      if (this.hasIndicatorTarget) this.indicatorTarget.classList.add("is-loading")
      Turbo.visit(window.location.href, { action: "replace" })
    }
    this.pulling = false
    if (this.hasIndicatorTarget) {
      this.indicatorTarget.style.transform = ""
      this.indicatorTarget.classList.remove("is-loading")
    }
  }
}