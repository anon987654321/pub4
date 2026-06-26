import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { threshold: { type: Number, default: 64 } }

  connect() {
    this.startY = 0
    this.currentY = 0
    this.dragging = false
    this.onTouchStart = this.touchStart.bind(this)
    this.onTouchMove = this.touchMove.bind(this)
    this.onTouchEnd = this.touchEnd.bind(this)
    this.element.addEventListener("touchstart", this.onTouchStart, { passive: true })
    this.element.addEventListener("touchmove", this.onTouchMove, { passive: false })
    this.element.addEventListener("touchend", this.onTouchEnd, { passive: true })
    this.element.addEventListener("touchcancel", this.onTouchEnd, { passive: true })
  }

  disconnect() {
    this.element.removeEventListener("touchstart", this.onTouchStart)
    this.element.removeEventListener("touchmove", this.onTouchMove)
    this.element.removeEventListener("touchend", this.onTouchEnd)
    this.element.removeEventListener("touchcancel", this.onTouchEnd)
  }

  touchStart(event) {
    if (window.scrollY > 0) return
    this.dragging = true
    this.startY = event.touches[0].clientY
    this.currentY = this.startY
  }

  touchMove(event) {
    if (!this.dragging) return
    this.currentY = event.touches[0].clientY
    const delta = this.currentY - this.startY
    if (delta > 0) event.preventDefault()
  }

  touchEnd() {
    if (!this.dragging) return
    const delta = this.currentY - this.startY
    this.dragging = false

    if (delta >= this.thresholdValue) {
      window.Turbo?.visit(window.location.href, { action: "replace" })
    }
  }
}
