import { Controller } from "@hotwired/stimulus"

const STORAGE_KEY = "pub4:newsletter-capture"
const REOPEN_AFTER_MS = 7 * 24 * 60 * 60 * 1000

export default class extends Controller {
  static targets = [ "dialog", "email" ]
  static values = { delay: { type: Number, default: 12000 } }

  connect() {
    this.dismissed = false
    this.timer = window.setTimeout(() => this.reveal(), this.delayValue)
    this.onSubmit = () => this.remember()
    this.element.addEventListener("submit", this.onSubmit)
  }

  disconnect() {
    window.clearTimeout(this.timer)
    this.element.removeEventListener("submit", this.onSubmit)
  }

  reveal() {
    if (this.dismissed || !this.eligible()) return
    if (typeof this.dialogTarget.showModal === "function") {
      this.dialogTarget.showModal()
    } else {
      this.dialogTarget.setAttribute("open", "open")
    }
    requestAnimationFrame(() => this.emailTarget.focus())
  }

  close() {
    this.dismissed = true
    this.dialogTarget.close?.()
    this.dialogTarget.removeAttribute("open")
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
    if (event.target === this.dialogTarget) this.close()
  }
}
