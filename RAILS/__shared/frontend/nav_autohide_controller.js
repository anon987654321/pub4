import { Controller } from "@hotwired/stimulus"

// Signs that a reader is present rather than a page that has merely loaded.
// touchstart is absent on purpose: it already reveals, and a tap that reveals
// should not also be the tap that starts the bar's countdown.
const ARM_EVENTS = ["pointermove", "scroll", "wheel", "keydown", "touchmove"]

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
//
// edge/zone exist because a hidden bar cannot be hovered. pointerenter fires on
// the element, and once the element has translated off-screen there is nothing
// under the cursor to enter — so on a mouse the bar left and never came back.
// Touch had document-level touchstart and the keyboard had focusin; the mouse
// had nothing. `zone` watches the last N pixels against `edge` and reveals when
// the pointer arrives there, which is how a video player's chrome behaves and
// what a reader already expects at a screen edge.
//
// The countdown starts at the reader's first sign of engagement, not at load.
// A timer armed on connect spends itself while the page is still painting and
// while the reader is still deciding where to look, so the bar left before it
// had been read — it measured the browser's progress rather than the reader's.
// Holding until a move, scroll, wheel or keypress means a reader who has not
// arrived yet keeps the nav, and one who is already moving gets the same delay
// they always did, counted from the moment they were actually there.
export default class extends Controller {
  static classes = ["hidden"]
  static values = {
    delay: { type: Number, default: 4000 },
    idle: { type: Number, default: 2500 },
    edge: { type: String, default: "top" },
    zone: { type: Number, default: 0 },
    // "activity" waits for the reader; "load" starts counting immediately, for
    // a surface that genuinely wants the bar gone whether or not anyone is there.
    arm: { type: String, default: "activity" },
    // Scrolling is the reader saying they are reading the page, not the bar.
    // Off by default: a transport bar is a control surface you scroll past and
    // still want, while a wayfinding bar has already done its job by then.
    // Pairs with zone, which is the way back.
    hideOnScroll: { type: Boolean, default: false },
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

    if (this.zoneValue > 0) {
      this.onPointerMove = this.revealFromEdge.bind(this)
      document.addEventListener("pointermove", this.onPointerMove, { passive: true })
    }

    if (this.hideOnScrollValue) {
      this.onScroll = this.hideForScroll.bind(this)
      document.addEventListener("scroll", this.onScroll, { passive: true })
    }

    if (this.armValue === "load") this.scheduleHide(this.delayValue)
    else this.armOnActivity()
  }

  disconnect() {
    this.clear()
    this.element.removeEventListener("pointerenter", this.onReveal)
    this.element.removeEventListener("pointerdown", this.onReveal)
    this.element.removeEventListener("focusin", this.onReveal)
    this.element.removeEventListener("pointerleave", this.onLeave)
    document.removeEventListener("touchstart", this.onReveal)
    if (this.onPointerMove) document.removeEventListener("pointermove", this.onPointerMove)
    if (this.onScroll) document.removeEventListener("scroll", this.onScroll)
    this.disarm()
  }

  // The first move, scroll, wheel or keypress is the reader arriving. Until one
  // of those happens the bar simply stays, however long the page has been open.
  // once:true on every listener means this costs nothing after it has fired.
  armOnActivity() {
    this.onActivity = () => {
      this.disarm()
      this.scheduleHide(this.delayValue)
    }
    ARM_EVENTS.forEach((name) =>
      document.addEventListener(name, this.onActivity, { passive: true, once: true }))
  }

  disarm() {
    if (!this.onActivity) return
    ARM_EVENTS.forEach((name) => document.removeEventListener(name, this.onActivity))
    this.onActivity = null
  }

  // Only acts while hidden, and only from the edge this bar lives on, so a
  // pointer crossing the page does not keep waking a bar it never approached.
  revealFromEdge(event) {
    if (!this.element.classList.contains(this.hiddenClassName)) return

    const y = event.clientY
    const near = this.edgeValue === "bottom"
      ? y >= window.innerHeight - this.zoneValue
      : y <= this.zoneValue
    if (near) this.reveal()
  }

  // Straight to hidden rather than a shortened countdown: the reader has moved
  // the page under the bar, which is the clearest statement that the bar is not
  // what they are looking at. The edge zone is how it comes back.
  hideForScroll() {
    if (this.element.contains(document.activeElement)) return
    if (this.prefersReducedMotion) return

    this.clear()
    this.disarm()
    this.element.classList.add(this.hiddenClassName)
  }

  reveal() {
    this.clear()
    // A reveal is itself the reader arriving, so the pending arm has nothing
    // left to wait for — without this it would fire later and quietly restart
    // the countdown with the longer opening delay.
    this.disarm()
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
