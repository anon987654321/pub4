import { Controller } from "@hotwired/stimulus"

// Dating's first screen: "sveip for å begynne". A swipe in any direction, or the
// link itself, opens the deck; without script the link alone does, so the page
// works as plain HTML. The heart is a css-doodle program written in the view;
// the library is fetched here, on this screen only, and not at all when the
// reader asks for reduced motion, which keeps the still SVG heart instead.
export default class extends Controller {
  static values = { url: String }
  static targets = ["doodle"]

  connect() {
    this.origin = null
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return

    import("css-doodle").catch(() => {})
  }

  pointerDown(event) {
    this.origin = { x: event.clientX, y: event.clientY }
  }

  pointerUp(event) {
    if (!this.origin) return

    const travel = Math.hypot(event.clientX - this.origin.x, event.clientY - this.origin.y)
    this.origin = null
    if (travel >= 48) this.start()
  }

  start() {
    window.Turbo ? window.Turbo.visit(this.urlValue) : window.location.assign(this.urlValue)
  }
}
