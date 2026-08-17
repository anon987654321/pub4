import { Controller } from "@hotwired/stimulus"

// The primary nav shows itself, then gets out of the way.
//
// It was permanent (operator decision 2026-08-08) because a drawer had been
// dodging a collision with .compose-trigger rather than resolving it. That
// collision is resolved — .app-shell is inset below the bar — so the bar can
// retire without the old problem coming back. It rests visible long enough to be
// read, slides up, and comes back on any sign the reader wants it.
//
// What it does NOT do is collapse the band it occupies. The wordmark and the
// theme control are fixed above this bar at a higher z-index, so the strip stays
// occupied when the links leave; nothing reflows, and the page does not jump
// under the reader's thumb at the moment the timer fires.
//
// Usage:
//   <div class="nav_swiper" data-controller="nav-autohide"
//        data-nav-autohide-delay-value="4000">
export default class extends Controller {
  static classes = ["hidden"]
  static values = {
    delay: { type: Number, default: 4000 },
    idle: { type: Number, default: 2500 },
  }

  connect() {
    this.hiddenClassName = this.hasHiddenClass ? this.hiddenClass : "nav_swiper--hidden"
    this.onReveal = this.reveal.bind(this)
    this.onLeave = this.scheduleHide.bind(this)

    // Revealing is deliberately cheap to trigger: a pointer anywhere on the bar,
    // a touch, a click, or a Tab into it. focusin is the one that matters for a
    // keyboard user — the links stay in the tab order while hidden, so without it
    // focus would land on something invisible.
    this.element.addEventListener("pointerenter", this.onReveal)
    this.element.addEventListener("pointerdown", this.onReveal)
    this.element.addEventListener("focusin", this.onReveal)
    this.element.addEventListener("pointerleave", this.onLeave)
    document.addEventListener("touchstart", this.onReveal, { passive: true })

    this.scheduleHide(this.delayValue)
  }

  disconnect() {
    this.clear()
    this.element.removeEventListener("pointerenter", this.onReveal)
    this.element.removeEventListener("pointerdown", this.onReveal)
    this.element.removeEventListener("focusin", this.onReveal)
    this.element.removeEventListener("pointerleave", this.onLeave)
    document.removeEventListener("touchstart", this.onReveal)
  }

  reveal() {
    this.clear()
    this.element.classList.remove(this.hiddenClassName)
    this.scheduleHide()
  }

  // The argument exists so the first hide can wait longer than later ones: the
  // opening delay is "long enough to read nine names", the idle delay is "you
  // touched it and then stopped".
  scheduleHide(after = this.idleValue) {
    this.clear()
    if (this.prefersReducedMotion) return

    this.timer = setTimeout(() => {
      // Never pull the bar out from under a keyboard user who is inside it.
      if (this.element.contains(document.activeElement)) return this.scheduleHide()

      this.element.classList.add(this.hiddenClassName)
    }, after)
  }

  clear() {
    if (this.timer) clearTimeout(this.timer)
    this.timer = null
  }

  // A reader who has asked for less motion has asked for less of exactly this.
  // Staying put is the accessible answer, not sliding more slowly.
  get prefersReducedMotion() {
    return window.matchMedia?.("(prefers-reduced-motion: reduce)").matches === true
  }
}
