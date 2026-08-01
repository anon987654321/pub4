import { Controller } from "@hotwired/stimulus"

const VALUE_KEY = "install-prompt-value"
const DISMISSED_KEY = "install-prompt-dismissed"

// Progressive install: only after real product value (post / play / chat).
// Value is marked via: window.dispatchEvent(new CustomEvent("pub4:install-value"))
// or data-action that calls install-prompt#markValue.
// Visit-count prompts were removed — they fire before the product is useful.
export default class extends Controller {
  connect() {
    this.deferredPrompt = null

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
    const valued = localStorage.getItem(VALUE_KEY) === "1"
    return valued && localStorage.getItem(DISMISSED_KEY) !== "1" && this.deferredPrompt
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
