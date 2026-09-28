import { Controller } from "@hotwired/stimulus"

const STORAGE_KEY = "pub4:newsletter-capture"
const REOPEN_AFTER_MS = 7 * 24 * 60 * 60 * 1000

export default class extends Controller {
  static targets = [ "email" ]
  static values = { delay: { type: Number, default: 12000 } }

  connect() {
    this.dismissed = false
    this.timer = window.setTimeout(() => this.reveal(), this.delayValue)
  }

  disconnect() {
    window.clearTimeout(this.timer)
  }

  reveal() {
    if (this.dismissed || !this.eligible()) return
    if (typeof this.element.showModal === "function") {
      this.element.showModal()
    } else {
      this.element.setAttribute("open", "open")
    }
    requestAnimationFrame(() => this.emailTarget.focus())
  }

  close() {
    this.dismissed = true
    this.element.close?.()
    this.element.removeAttribute("open")
    this.remember()
  }

  remember() {
    try {
      window.localStorage.setItem(STORAGE_KEY, String(Date.now()))
    } catch (_) {}
  }

  eligible() {
    try {
      const last = Number(window.localStorage.getItem(STORAGE_KEY) || 0)
      return Date.now() - last >= REOPEN_AFTER_MS
    } catch (_) {
      return true
    }
  }

  backdropClose(event) {
    if (event.target === this.element) this.close()
  }
}
