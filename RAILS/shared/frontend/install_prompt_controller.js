import { Controller } from "@hotwired/stimulus"
import { installDismissedKey } from "pub4/pwa_standalone"
import { announceInstallVisible } from "pub4/onboarding"

const VALUE_KEY = "install-prompt-value"
// The unscoped key stays readable so a dismissal from before the key was
// namespaced still counts; only new writes are scoped.
const LEGACY_DISMISSED_KEY = "install-prompt-dismissed"

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
    return valued && !this.dismissed() && this.deferredPrompt
  }

  dismissed() {
    return [installDismissedKey(), LEGACY_DISMISSED_KEY].some(key => localStorage.getItem(key) === "1")
  }

  reveal() {
    if (!this.canShow()) return
    if (!this.element.hidden) return

    this.element.hidden = false
    // Install outranks the menu coach and the push button, and it can appear at
    // any moment — the visitor posts, plays a track, sends a message. Whichever
    // of the other two is already open steps back rather than stacking.
    announceInstallVisible()
  }

  dismiss() {
    localStorage.setItem(installDismissedKey(), "1")
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
