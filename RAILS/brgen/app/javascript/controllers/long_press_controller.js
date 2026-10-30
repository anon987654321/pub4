import { Controller } from "@hotwired/stimulus"
import Haptics from "pub4/haptics"

// Press and hold a card to open its own "more" menu: the same menu, the same
// actions, and the button stays the keyboard and screen-reader way in. Android
// fires contextmenu on a long press, and so do a desktop right click and
// Shift+F10; all of them open the menu.
//
// Links, media, fields and selected text keep the browser's own press, because
// copying a link, saving an image and selecting text are what a long press
// means there.
const NATIVE = "a, button, input, textarea, select, img, video, audio, label, summary, [contenteditable]"
const SLOP_PX = 8

export default class extends Controller {
  static targets = ["trigger"]
  static values = { delay: { type: Number, default: 500 } }

  disconnect() {
    this.cancel()
  }

  start(event) {
    if (!event.isPrimary || event.button > 0 || this.#native(event)) return

    this.origin = { x: event.clientX, y: event.clientY }
    this.timer = setTimeout(() => this.#open(), this.delayValue)
  }

  // A press that travels is a scroll or a swipe, not a hold.
  move(event) {
    if (!this.origin) return
    if (Math.hypot(event.clientX - this.origin.x, event.clientY - this.origin.y) > SLOP_PX) this.cancel()
  }

  cancel() {
    clearTimeout(this.timer)
    this.timer = null
    this.origin = null
  }

  context(event) {
    if (this.#native(event)) return

    event.preventDefault()
    this.#open()
  }

  // Lifting the finger after the hold sends a click, and the dropdown closes on
  // any window click; swallowed here in the capture phase, once.
  swallow(event) {
    if (!this.opened) return

    event.preventDefault()
    event.stopPropagation()
    this.opened = false
  }

  #open() {
    this.cancel()
    if (!this.hasTriggerTarget || this.triggerTarget.getAttribute("aria-expanded") === "true") return

    Haptics.pulse(10)
    this.opened = true
    setTimeout(() => { this.opened = false }, 700)
    this.triggerTarget.click()
    this.triggerTarget.focus({ preventScroll: true })
  }

  #native(event) {
    return Boolean(event.target.closest?.(NATIVE)) || String(window.getSelection?.() || "").length > 0
  }
}
