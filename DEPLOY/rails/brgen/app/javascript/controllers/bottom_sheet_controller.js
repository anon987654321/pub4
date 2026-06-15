import { Controller } from "@hotwired/stimulus"

const SNAP = [0, 0.5, 1]

export default class extends Controller {
  static targets = ["panel", "handle"]
  static values = { snap: { type: Number, default: 0 } }

  connect() {
    this.panelTarget.style.transition = "transform 0.35s cubic-bezier(0.32, 0.72, 0, 1)"
    this.updateSnap()
  }

  drag(event) {
    const y = Math.max(0, event.detail?.offsetY || 0)
    this.panelTarget.style.transform = `translateY(${y}px)`
  }

  release(event) {
    const height = this.panelTarget.offsetHeight
    const offset = Math.max(0, event.detail?.offsetY || 0)
    const ratio = offset / height
    this.snapValue = SNAP.reduce((best, point) => Math.abs(point - ratio) < Math.abs(best - ratio) ? point : best)
    this.updateSnap()
  }

  updateSnap() {
    const offset = (1 - this.snapValue) * this.panelTarget.offsetHeight
    this.panelTarget.style.transform = `translateY(${offset}px)`
  }
}