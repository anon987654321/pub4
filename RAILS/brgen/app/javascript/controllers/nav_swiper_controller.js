import { Controller } from "@hotwired/stimulus"

// Pull-down top-drawer nav. Hidden by default; swipe down from the top edge
// (or click the grip) reveals it. Swipe up, tap away, or Escape hides it.
export default class extends Controller {
  static targets = ["root", "grip"]

  connect() {
    this.revealed = false
    this.startY = null
    this.tracking = false
    this.edge = 44        // px from top that arms a downward reveal swipe
    this.threshold = 40   // px of travel to commit

    this.onStart = this.onStart.bind(this)
    this.onMove = this.onMove.bind(this)
    this.onEnd = this.onEnd.bind(this)
    this.onAway = this.onAway.bind(this)
    this.onKey = this.onKey.bind(this)

    window.addEventListener("touchstart", this.onStart, { passive: true })
    window.addEventListener("touchmove", this.onMove, { passive: true })
    window.addEventListener("touchend", this.onEnd, { passive: true })
    window.addEventListener("pointerdown", this.onStart, { passive: true })
    window.addEventListener("pointerup", this.onEnd, { passive: true })
    // Only touchmove was bound, so a mouse could never complete the reveal
    // gesture — the grip pill was desktop's only way in, which is why removing
    // it needed a replacement first. A hover into the top few pixels is the
    // mouse equivalent of the swipe, and costs no permanent chrome.
    this.onHover = this.onHover.bind(this)
    if (window.matchMedia("(hover: hover)").matches) {
      window.addEventListener("pointermove", this.onHover, { passive: true })
    }
    document.addEventListener("click", this.onAway, true)
    document.addEventListener("keydown", this.onKey)
  }

  onHover(e) {
    if (e.pointerType === "touch") return
    if (!this.revealed && e.clientY <= 2) this.show()
  }

  disconnect() {
    window.removeEventListener("touchstart", this.onStart)
    window.removeEventListener("touchmove", this.onMove)
    window.removeEventListener("touchend", this.onEnd)
    window.removeEventListener("pointerdown", this.onStart)
    window.removeEventListener("pointerup", this.onEnd)
    window.removeEventListener("pointermove", this.onHover)
    document.removeEventListener("click", this.onAway, true)
    document.removeEventListener("keydown", this.onKey)
  }

  _y(e) {
    return e.clientY ?? (e.touches && e.touches[0] && e.touches[0].clientY) ?? null
  }

  onStart(e) {
    const y = this._y(e)
    if (y === null) return
    // Arm a reveal only when the gesture begins right at the top edge.
    if (!this.revealed && y <= this.edge) { this.tracking = true; this.startY = y }
    // When open, arm an upward dismiss anywhere over the bar.
    else if (this.revealed) { this.tracking = true; this.startY = y }
  }

  onMove(e) {
    if (!this.tracking || this.startY === null) return
    const y = this._y(e)
    if (y === null) return
    const dy = y - this.startY
    if (!this.revealed && dy > this.threshold) { this.show(); this.tracking = false }
    else if (this.revealed && dy < -this.threshold) { this.hide(); this.tracking = false }
  }

  onEnd() { this.tracking = false; this.startY = null }

  onAway(e) {
    if (this.revealed && !this.rootTarget.contains(e.target)) this.hide()
  }

  onKey(e) {
    if (e.key === "Escape" && this.revealed) this.hide()
  }

  toggle() { this.revealed ? this.hide() : this.show() }

  show() {
    this.revealed = true
    this.rootTarget.classList.add("revealed")
    if (this.hasGripTarget) this.gripTarget.setAttribute("aria-expanded", "true")
  }

  hide() {
    this.revealed = false
    this.rootTarget.classList.remove("revealed")
    if (this.hasGripTarget) this.gripTarget.setAttribute("aria-expanded", "false")
  }
}
