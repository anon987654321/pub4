import { Controller } from "@hotwired/stimulus"

// Pointer parallax for the in-feed affiliate unit, replacing the Parallax.js +
// jQuery pair the original pen used. Each tile declares its own depth, so the
// band separates into layers as the pointer crosses it.
//
// Three things the pen did that this deliberately does not:
//
//   - read layout inside the move handler. The container rect is measured on
//     connect and on resize, never per event, because design_rules forbids
//     layout reads in an animation loop and this one fires at pointer rate.
//   - animate on every event. Moves are coalesced into one rAF, so a fast
//     pointer costs one write per frame rather than one per event.
//   - move at all when the visitor asked for stillness. prefers-reduced-motion
//     leaves every tile at rest; the unit is legible without the effect, which
//     is the test for whether motion is decoration.
export default class extends Controller {
  static targets = ["tile"]
  static values = { strength: { type: Number, default: 18 } }

  connect() {
    this.reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches
    if (this.reduced) return

    this.frame = null
    this.measure()
    this.onResize = () => this.measure()
    window.addEventListener("resize", this.onResize, { passive: true })
  }

  disconnect() {
    if (this.frame) cancelAnimationFrame(this.frame)
    if (this.onResize) window.removeEventListener("resize", this.onResize)
  }

  measure() {
    const rect = this.element.getBoundingClientRect()
    this.centerX = rect.left + rect.width / 2
    this.centerY = rect.top + rect.height / 2
    this.halfW = rect.width / 2 || 1
    this.halfH = rect.height / 2 || 1
  }

  move(event) {
    if (this.reduced) return

    // Store only; the write happens in the frame below.
    this.pointerX = event.clientX
    this.pointerY = event.clientY
    if (this.frame) return

    this.frame = requestAnimationFrame(() => {
      this.frame = null
      this.apply()
    })
  }

  leave() {
    if (this.reduced) return

    this.pointerX = this.centerX
    this.pointerY = this.centerY
    this.apply()
  }

  apply() {
    const dx = (this.pointerX - this.centerX) / this.halfW
    const dy = (this.pointerY - this.centerY) / this.halfH

    this.tileTargets.forEach((tile) => {
      const depth = parseFloat(tile.dataset.parallaxTiltDepth || "0")
      const shiftX = (-dx * depth * this.strengthValue).toFixed(2)
      const shiftY = (-dy * depth * this.strengthValue).toFixed(2)
      tile.style.transform = `translate3d(${shiftX}px, ${shiftY}px, 0)`
    })
  }
}
