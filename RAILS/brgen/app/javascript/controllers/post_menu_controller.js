import { Controller } from "@hotwired/stimulus"

// The feed card's more-actions disclosure. The vendored dropdown only toggled a
// class: aria-expanded stayed "false", Escape did nothing and focus stayed on
// the trigger, so a keyboard user opened a menu they could not see into. This
// keeps the disclosure pattern (the list holds a quote form, so it is not an
// ARIA menu) and adds what a menu button owes the keyboard: focus the first
// item on open, Escape closes, and focus goes back to the trigger.
const ITEMS = "a[href], button:not([disabled]), textarea, input:not([type=hidden])"

export default class extends Controller {
  static targets = ["button", "menu"]

  toggle() {
    this.open ? this.close() : this.show()
  }

  show() {
    this.#expand(true)
    this.menuTarget.querySelector(ITEMS)?.focus()
  }

  close({ restoreFocus = true } = {}) {
    if (!this.open) return

    this.#expand(false)
    if (restoreFocus) this.buttonTarget.focus()
  }

  // A click anywhere else closes the list without pulling focus back.
  hide(event) {
    if (!this.element.contains(event.target)) this.close({ restoreFocus: false })
  }

  keydown(event) {
    if (event.key !== "Escape" || !this.open) return

    event.preventDefault()
    this.close()
  }

  get open() {
    return this.buttonTarget.getAttribute("aria-expanded") === "true"
  }

  #expand(open) {
    const { classList } = this.menuTarget
    classList.toggle("hidden", !open)
    this.buttonTarget.setAttribute("aria-expanded", String(open))
  }
}
