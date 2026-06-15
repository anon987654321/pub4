import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { threshold: { type: Number, default: 80 } }

  connect() {
    this.startX = 0
    this.startY = 0
  }

  touchstart(event) {
    this.startX = event.touches[0].clientX
    this.startY = event.touches[0].clientY
  }

  touchend(event) {
    const dx = event.changedTouches[0].clientX - this.startX
    const dy = event.changedTouches[0].clientY - this.startY
    if (Math.abs(dx) < this.thresholdValue || Math.abs(dx) < Math.abs(dy)) return

    this.element.dispatchEvent(new CustomEvent(dx > 0 ? "swipe:right" : "swipe:left", { bubbles: true }))
  }
}