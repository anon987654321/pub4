import { Controller } from "@hotwired/stimulus"

// Publishes the on-screen keyboard's height as --keyboard-inset.
//
// env(keyboard-inset-height) is the VirtualKeyboard API. That API is Chromium
// only, and even there the env stays 0px until overlaysContent is opted in.
// Safari — the phone this fleet is actually used on — never ships it. The
// compose box and the messenger dock were padding against a value that is
// always 0 on iOS, so the keyboard covered the field.
//
// visualViewport is the reader that exists on iOS: remainder of innerHeight
// minus the visual viewport, ignoring the ~URL-bar jitter below KEYBOARD_MIN.
export default class extends Controller {
  static KEYBOARD_MIN = 80

  connect() {
    this.viewport = window.visualViewport
    this.onChange = () => this.schedule()
    this.frame = null
    if (this.viewport) {
      this.viewport.addEventListener("resize", this.onChange, { passive: true })
      this.viewport.addEventListener("scroll", this.onChange, { passive: true })
    }
    window.addEventListener("focusout", this.onChange, { passive: true })
    this.apply()
  }

  disconnect() {
    if (this.frame) cancelAnimationFrame(this.frame)
    if (this.viewport && this.onChange) {
      this.viewport.removeEventListener("resize", this.onChange)
      this.viewport.removeEventListener("scroll", this.onChange)
    }
    window.removeEventListener("focusout", this.onChange)
    document.documentElement.style.removeProperty("--keyboard-inset")
  }

  schedule() {
    if (this.frame) return
    this.frame = requestAnimationFrame(() => {
      this.frame = null
      this.apply()
    })
  }

  apply() {
    const vv = this.viewport
    let inset = 0
    if (vv) {
      const remainder = window.innerHeight - vv.height - vv.offsetTop
      if (remainder > this.constructor.KEYBOARD_MIN && this.#editing()) inset = remainder
    }
    document.documentElement.style.setProperty("--keyboard-inset", `${Math.round(inset)}px`)
  }

  #editing() {
    const el = document.activeElement
    if (!el) return false
    const tag = el.tagName
    return tag === "INPUT" || tag === "TEXTAREA" || el.isContentEditable
  }
}
