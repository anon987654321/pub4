import { Controller } from "@hotwired/stimulus"

const VISITS_KEY = "install-prompt-visits"
const VALUE_KEY = "install-prompt-value"
const DISMISSED_KEY = "install-prompt-dismissed"

// Show after real product value (post / play / chat) OR three visits.
// Value is marked via: window.dispatchEvent(new CustomEvent("pub4:install-value"))
// or data-action that calls install-prompt#markValue.
export default class extends Controller {
  connect() {
    this.deferredPrompt = null
    const visits = Number(localStorage.getItem(VISITS_KEY) || "0") + 1
    localStorage.setItem(VISITS_KEY, String(visits))

    this.onBeforeInstall = (event) => {
      event.preventDefault()
      this.deferredPrompt = event
      this.reveal()
    }
    this.onValue = () => this.markValue()

    window.addEventListener("beforeinstallprompt", this.onBeforeInstall)
    window.addEventListener("pub4:install-value", this.onValue)
    this.reveal()
  }

  disconnect() {
    window.removeEventListener("beforeinstallprompt", this.onBeforeInstall)
    window.removeEventListener("pub4:install-value", this.onValue)
  }

  markValue() {
    try { localStorage.setItem(VALUE_KEY, "1") } catch (_) {}
    this.reveal()
  }

  canShow() {
    const visits = Number(localStorage.getItem(VISITS_KEY) || "0")
    const valued = localStorage.getItem(VALUE_KEY) === "1"
    const ready = valued || visits >= 3
    return ready && localStorage.getItem(DISMISSED_KEY) !== "1" && this.deferredPrompt
  }

  reveal() {
    if (this.canShow()) this.element.hidden = false
  }

  dismiss() {
    localStorage.setItem(DISMISSED_KEY, "1")
    this.element.hidden = true
  }

  async install() {
    if (!this.deferredPrompt) return
    this.deferredPrompt.prompt()
    await this.deferredPrompt.userChoice
    this.deferredPrompt = null
    this.element.hidden = true
  }
}
