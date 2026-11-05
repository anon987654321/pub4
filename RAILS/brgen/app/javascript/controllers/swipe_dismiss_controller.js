import { Controller } from "@hotwired/stimulus"
import Haptics from "pub4/haptics"

// Swipe a notification left to dismiss it. The swipe only presses the row's own
// Dismiss button, so the server, the stream and the no-JavaScript path stay the
// button's; a row that fails to go simply stays, with the button still there.
//
// A press that moves more up or down than sideways is a scroll and is left to
// the page (.notification-card's touch-action: pan-y keeps vertical scrolling native).
//
// A swipe is easy to make by accident, so it hides the row and offers Undo
// before anything is deleted. There is no timer on the offer (WCAG 2.2.1, the
// rule shared/_flash_toasts states for an undo): the dismissal is sent when the
// reader swipes the next row away, or leaves the page, and not before.
const START_PX = 10
const DISMISS_RATIO = 0.35

// One row waits at a time; swiping a second one sends the first.
let held = null

export default class extends Controller {
  static targets = ["button"]
  static values = { done: String, undo: String }

  // A row redrawn by the inbox stream while it waits comes back as a new
  // element; this one was never sent, so nothing is lost.
  disconnect() {
    if (held === this) this.#release()
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
      try { this.element.setPointerCapture?.(event.pointerId) } catch { /* a pointer the browser no longer tracks */ }
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
    if (dismiss) this.#hold()
  }

  reset() {
    this.origin = null
    this.dragging = false
    this.armed = false
    this.element.style.transform = ""
  }

  undo() {
    this.#release()
    this.element.hidden = false
    this.element.querySelector("a, button")?.focus()
  }

  #hold() {
    if (held && held !== this) held.#send()
    held = this
    this.element.hidden = true
    this.onLeave = () => this.#send({ leaving: true })
    document.addEventListener("turbo:before-visit", this.onLeave)
    window.addEventListener("pagehide", this.onLeave)
    this.#showToast()
  }

  // The row's own Dismiss form, posted with keepalive so it outlives a page
  // being left. Its stream answer is not applied: it redraws the whole list,
  // which would bring back a row that is waiting on its own Undo.
  #send({ leaving = false } = {}) {
    this.#release()
    const form = this.hasButtonTarget ? this.buttonTarget.form : null
    if (!form) return

    fetch(form.action, { method: "POST", body: new FormData(form), keepalive: true,
                         credentials: "same-origin", redirect: "manual" })
    if (!leaving) this.element.remove()
  }

  #release() {
    if (held === this) held = null
    document.removeEventListener("turbo:before-visit", this.onLeave)
    window.removeEventListener("pagehide", this.onLeave)
    this.toast?.remove()
    this.toast = null
  }

  #showToast() {
    const stack = document.querySelector(".toast-stack") || this.#newStack()

    const toast = document.createElement("div")
    toast.className = "toast notification-undo-toast"
    toast.setAttribute("role", "status")
    toast.setAttribute("aria-live", "polite")

    const text = document.createElement("span")
    text.textContent = this.doneValue

    const undo = document.createElement("button")
    undo.type = "button"
    undo.className = "button button-ghost button-small"
    undo.textContent = this.undoValue
    undo.addEventListener("click", () => this.undo())
    toast.append(text, undo)
    stack.append(toast)
    this.toast = toast
  }

  #newStack() {
    const stack = document.createElement("div")
    stack.className = "toast-stack"
    return document.body.appendChild(stack)
  }
}
