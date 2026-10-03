import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["sheet", "backdrop", "trigger"]
  static values = { level: { type: Number, default: 0 } }

  connect() {
    this.dragging = false
    this.startY = 0
    this.currentY = 0
    this.sync()
  }

  toggle() {
    this.levelValue = this.levelValue >= 2 ? 0 : this.levelValue + 1
    this.sync()
  }

  open() {
    this.levelValue = 2
    this.sync()
  }

  close() {
    this.levelValue = 0
    this.sync()
  }

  sync() {
    const sheet = this.sheetTarget
    if (!sheet) return
    sheet.dataset.level = String(this.levelValue)
    sheet.style.transform = `translateY(${100 - (this.levelValue * 50)}%)`
    if (this.hasBackdropTarget) {
      this.backdropTarget.dataset.open = this.levelValue > 0 ? "1" : "0"
    }
    // The trigger never reported its state, so a screen reader announced
    // "More, button" identically whether the sheet was open or shut. The closed
    // sheet is now visibility: hidden, out of the tree entirely, so this is the
    // only thing that says which way it is.
    if (this.hasTriggerTarget) {
      this.triggerTarget.setAttribute("aria-expanded", this.levelValue > 0 ? "true" : "false")
    }
  }

  pointerDown(event) {
    this.dragging = true
    this.startY = event.clientY || event.touches?.[0]?.clientY || 0
    this.currentY = this.startY
    this.sheetTarget.style.transition = "none"
  }

  pointerMove(event) {
    if (!this.dragging) return
    this.currentY = event.clientY || event.touches?.[0]?.clientY || 0
    const delta = this.currentY - this.startY
    const offset = Math.max(0, Math.min(100, 100 - (this.levelValue * 50) + (delta / 4)))
    this.sheetTarget.style.transform = `translateY(${offset}%)`
  }

  pointerUp() {
    if (!this.dragging) return
    this.dragging = false
    this.sheetTarget.style.transition = ""
    const delta = this.currentY - this.startY
    if (delta > 80) this.levelValue = Math.max(0, this.levelValue - 1)
    else if (delta < -80) this.levelValue = Math.min(2, this.levelValue + 1)
    this.sync()
  }
}
