import { Controller } from "@hotwired/stimulus"

// Edge-swipe-to-reveal drawer. Hidden by default; swipe in from the
// configured screen edge (or click the grip) reveals it. Swipe back
// toward the edge, tap away, or Escape hides it. One controller shared by
// every off-canvas panel (top nav, left sidebar, right widgets) instead of
// duplicating near-identical gesture logic per panel.
export default class extends Controller {
  static targets = ["root", "grip"]
  static values = {
    edge: { type: String, default: "top" },
    // First-visit reveal (operator, 2026-08-22): a drawer nobody has ever
    // seen is a feature nobody knows exists. With intro set, the panel
    // starts REVEALED until the visitor dismisses it once — swipe, tap
    // away, Escape, or the grip — and that dismissal is remembered per
    // panel. The swipe stays the recall gesture forever after.
    intro: { type: String, default: "" },
  }

  connect() {
    this.revealed = false
    if (this.introValue) {
      let seen = null
      try { seen = localStorage.getItem(`edge-swiper-intro:${this.introValue}`) } catch {}
      if (!seen) requestAnimationFrame(() => this.show())
    }
    this.startPos = null
    this.tracking = false
    this.armDistance = 44   // px from the edge that arms a reveal swipe
    this.threshold = 40     // px of travel to commit show/hide

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
    document.addEventListener("click", this.onAway, true)
    document.addEventListener("keydown", this.onKey)
  }

  disconnect() {
    window.removeEventListener("touchstart", this.onStart)
    window.removeEventListener("touchmove", this.onMove)
    window.removeEventListener("touchend", this.onEnd)
    window.removeEventListener("pointerdown", this.onStart)
    window.removeEventListener("pointerup", this.onEnd)
    document.removeEventListener("click", this.onAway, true)
    document.removeEventListener("keydown", this.onKey)
  }

  // Position along the gesture axis: Y for a top edge, X for left/right.
  _pos(e) {
    if (this.edgeValue === "top") return e.clientY ?? (e.touches && e.touches[0]?.clientY) ?? null
    return e.clientX ?? (e.touches && e.touches[0]?.clientX) ?? null
  }

  // Screen extent along the gesture axis, for measuring distance from an edge.
  _extent() {
    return this.edgeValue === "top" ? window.innerHeight : window.innerWidth
  }

  _nearEdge(pos) {
    if (this.edgeValue === "right") return this._extent() - pos <= this.armDistance
    return pos <= this.armDistance
  }

  // Sign of travel that counts as "toward reveal" for this edge.
  _revealSign() {
    return this.edgeValue === "right" ? -1 : 1
  }

  onStart(e) {
    const pos = this._pos(e)
    if (pos === null) return
    if (!this.revealed && this._nearEdge(pos)) { this.tracking = true; this.startPos = pos }
    else if (this.revealed) { this.tracking = true; this.startPos = pos }
  }

  onMove(e) {
    if (!this.tracking || this.startPos === null) return
    const pos = this._pos(e)
    if (pos === null) return
    const delta = (pos - this.startPos) * this._revealSign()
    if (!this.revealed && delta > this.threshold) { this.show(); this.tracking = false }
    else if (this.revealed && delta < -this.threshold) { this.hide(); this.tracking = false }
  }

  onEnd() { this.tracking = false; this.startPos = null }

  onAway(e) {
    if (this.revealed && !this.rootTarget.contains(e.target)) this.hide()
  }

  onKey(e) {
    if (e.key === "Escape" && this.revealed) this.hide()
  }

  toggle() { this.revealed ? this.hide() : this.show() }

  // A revealed drawer is an opaque, full-height panel. Anything fixed beneath it
  // is invisible AND unclickable, while still being a tab stop and still counting
  // as a target. The drawer cannot be a CSS sibling of that chrome — .tab-bar-peel
  // hangs off .app-shell while the drawer sits inside .layout — so the state goes
  // on the root, where any of it can reach the fact.
  //
  // Recomputed from the DOM rather than counted, because two panels share this
  // controller and a counter would drift the first time one was removed while open.
  syncRootState() {
    const open = !!document.querySelector('[data-controller~="edge-swiper"].revealed')
    document.documentElement.classList.toggle("drawer-open", open)
  }

  show() {
    this.revealed = true
    // The wrapper, not the root target: the CSS keys .sidebar-swiper.revealed
    // .sidebar, and classing the aside itself matched nothing — the reveal
    // toggled state and painted NOTHING, on every panel, since the split.
    // Found 2026-08-22 proving the first-visit intro; the 'deliberately
    // hidden' nav was hiding a dead reveal.
    this.element.classList.add("revealed")
    if (this.hasGripTarget) this.gripTarget.setAttribute("aria-expanded", "true")
    this.syncRootState()
  }

  hide() {
    if (this.introValue) {
      try { localStorage.setItem(`edge-swiper-intro:${this.introValue}`, "1") } catch {}
    }
    this.revealed = false
    this.element.classList.remove("revealed")
    if (this.hasGripTarget) this.gripTarget.setAttribute("aria-expanded", "false")
    this.syncRootState()
  }
}
