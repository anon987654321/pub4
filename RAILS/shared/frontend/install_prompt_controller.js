import { Controller } from "@hotwired/stimulus"

const VISITS_KEY = "install-prompt-visits"
const DISMISSED_KEY = "install-prompt-dismissed"

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

    window.addEventListener("beforeinstallprompt", this.onBeforeInstall)
    this.reveal()
  }

  disconnect() {
    window.removeEventListener("beforeinstallprompt", this.onBeforeInstall)
  }

  canShow() {
    const visits = Number(localStorage.getItem(VISITS_KEY) || "0")
    return visits >= 3 && localStorage.getItem(DISMISSED_KEY) !== "1" && this.deferredPrompt
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
