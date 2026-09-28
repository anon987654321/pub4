import { Controller } from "@hotwired/stimulus"
import { mayPrompt, setWelcomePending } from "pub4/onboarding"

const KEY_PREFIX = "pub4:welcome-onboarding:"
const FOCUSABLE = "a[href], area[href], button:not([disabled]), input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex='-1'])"

export default class extends Controller {
  static values = { surface: String }

  connect() {
    this.key = KEY_PREFIX + (this.surfaceValue || "default")
    this.previousFocus = null
    this.onConsent = () => this.reveal()
    this.onKeydown = (event) => this.handleKeydown(event)

    window.addEventListener("pub4:cookie-consent-resolved", this.onConsent)
    document.addEventListener("keydown", this.onKeydown)

    setWelcomePending(!this.dismissed())
    this.reveal()
  }

  disconnect() {
    window.removeEventListener("pub4:cookie-consent-resolved", this.onConsent)
    document.removeEventListener("keydown", this.onKeydown)
  }

  dismissed() {
    try {
      return localStorage.getItem(this.key) === "1"
    } catch (_) {
      return false
    }
  }

  reveal() {
    if (this.dismissed() || !mayPrompt("welcome")) {
      if (this.dismissed()) setWelcomePending(false)
      return
    }

    if (!this.element.hidden) return

    this.previousFocus = document.activeElement
    this.element.hidden = false
    requestAnimationFrame(() => this.firstFocusable()?.focus())
  }

  close() {
    try { localStorage.setItem(this.key, "1") } catch (_) {}
    this.element.hidden = true
    setWelcomePending(false)
    window.dispatchEvent(new CustomEvent("pub4:welcome-dismissed", {
      detail: { surface: this.surfaceValue || "default" }
    }))
    this.previousFocus?.focus?.()
  }

  handleKeydown(event) {
    if (this.element.hidden) return

    if (event.key === "Escape") {
      event.preventDefault()
      this.close()
      return
    }

    if (event.key !== "Tab") return
    const nodes = [...this.element.querySelectorAll(FOCUSABLE)].filter((node) => !node.hidden)
    if (nodes.length === 0) return

    const first = nodes[0]
    const last = nodes[nodes.length - 1]
    if (event.shiftKey && document.activeElement === first) {
      event.preventDefault()
      last.focus()
    } else if (!event.shiftKey && document.activeElement === last) {
      event.preventDefault()
      first.focus()
    }
  }

  firstFocusable() {
    return this.element.querySelector(FOCUSABLE)
  }
}