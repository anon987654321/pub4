// Progressive disclosure for the bottom tab bar ("footer menu").
//
// Hidden by default so the feed owns the screen; reveal on scroll-up or the
// peel grip. Hide again on scroll-down. Ported hide-on-scroll behavior from
// the real 2014 mobile.css footer.slide_down — flipped so closed is the default.
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["bar", "peel"]
  static values = {
    storageKey: { type: String, default: "pub4:tab-bar:open" }
  }

  connect() {
    this.lastY = this.element.scrollTop
    this.ticking = false
    this.threshold = 8 // px of travel before reacting, avoids jitter at rest

    // Default closed (progressive disclosure). Session restore only if the
    // visitor already opened it this tab — not across sessions.
    this.#apply(this.#restore() !== true)

    this.onScroll = this.onScroll.bind(this)
    this.element.addEventListener("scroll", this.onScroll, { passive: true })
  }

  disconnect() {
    this.element.removeEventListener("scroll", this.onScroll)
  }

  // Peel grip / explicit affordance.
  reveal(event) {
    event?.preventDefault()
    this.#apply(false)
  }

  hide(event) {
    event?.preventDefault()
    this.#apply(true)
  }

  toggle(event) {
    event?.preventDefault()
    this.#apply(!this.hidden)
  }

  get hidden() {
    return document.documentElement.classList.contains("chrome-hidden")
  }

  onScroll() {
    if (this.ticking) return
    this.ticking = true
    requestAnimationFrame(() => {
      const y = this.element.scrollTop
      const dy = y - this.lastY
      if (Math.abs(dy) > this.threshold) {
        // Scroll down → hide; scroll up → show. Stay hidden at the very top
        // until the visitor intentionally peels or scrolls back up mid-page.
        if (dy > 0 && y > this.threshold) this.#apply(true)
        else if (dy < 0) this.#apply(false)
        this.lastY = y
      }
      this.ticking = false
    })
  }

  #apply(hidden) {
    document.documentElement.classList.toggle("chrome-hidden", hidden)

    if (this.hasBarTarget) {
      this.barTarget.setAttribute("aria-hidden", hidden ? "true" : "false")
      if (hidden) this.barTarget.setAttribute("inert", "")
      else this.barTarget.removeAttribute("inert")
    }

    if (this.hasPeelTarget) {
      this.peelTarget.hidden = !hidden
      this.peelTarget.setAttribute("aria-expanded", hidden ? "false" : "true")
    }

    this.#persist(!hidden)
  }

  #persist(open) {
    try { window.sessionStorage.setItem(this.storageKeyValue, open ? "1" : "0") } catch (_) {}
  }

  #restore() {
    try { return window.sessionStorage.getItem(this.storageKeyValue) === "1" } catch (_) { return false }
  }
}
