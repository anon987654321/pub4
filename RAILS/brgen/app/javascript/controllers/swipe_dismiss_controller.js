import { Controller } from "@hotwired/stimulus"
import Haptics from "pub4/haptics"

// Swipe a notification left to dismiss it. The swipe only presses the row's own
// Dismiss button, so the server, the stream and the no-JavaScript path stay the
// button's; a row that fails to go simply stays, with the button still there.
//
// A press that moves more up or down than sideways is a scroll and is left to
// the page (touch-action: pan-y keeps vertical scrolling native).
const START_PX = 10
const DISMISS_RATIO = 0.35

export default class extends Controller {
  static targets = ["button"]

  connect() {
    this.element.style.touchAction = "pan-y"
  }

  start(event) {
    if (!event.isPrimary || event.button > 0 || event.target.closest("a, button, input, textarea")) return

    this.origin = { x: event.clientX, y: event.clientY }
    this.dragging = false
    this.armed = false
  }

  move(event) {
    if (!this.origin) return

    const dx = event.clientX - this.origin.x
    const dy = event.clientY - this.origin.y
    if (!this.dragging) {
      if (Math.abs(dy) > Math.abs(dx)) return this.reset()
      if (Math.abs(dx) < START_PX) return

      this.dragging = true
      this.element.setPointerCapture?.(event.pointerId)
    }

    const offset = Math.min(0, dx)
    this.element.style.transform = `translateX(${offset}px)`
    const armed = -offset > this.element.offsetWidth * DISMISS_RATIO
    if (armed && !this.armed) Haptics.pulse(10)
    this.armed = armed
  }

  end() {
    const dismiss = this.dragging && this.armed && this.hasButtonTarget
    this.reset()
    if (dismiss) this.buttonTarget.click()
  }

  reset() {
    this.origin = null
    this.dragging = false
    this.armed = false
    this.element.style.transform = ""
  }
}
