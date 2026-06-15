import { Controller } from "@hotwired/stimulus"
import { visitCount, installDismissed, dismissInstall } from "pwa/offline_store"

export default class extends Controller {
  static targets = ["banner", "installButton"]
  static values = { minVisits: { type: Number, default: 3 } }

  deferredPrompt = null

  connect() {
    window.addEventListener("beforeinstallprompt", this.#capturePrompt)
    window.addEventListener("appinstalled", this.#hideBanner)
    this.#maybeShowBanner()
  }

  disconnect() {
    window.removeEventListener("beforeinstallprompt", this.#capturePrompt)
    window.removeEventListener("appinstalled", this.#hideBanner)
  }

  #capturePrompt = event => {
    event.preventDefault()
    this.deferredPrompt = event
    this.#maybeShowBanner()
  }

  #hideBanner = () => {
    if (this.hasBannerTarget) this.bannerTarget.hidden = true
  }

  async #maybeShowBanner() {
    if (!this.hasBannerTarget || this.deferredPrompt == null) return
    if (window.matchMedia("(display-mode: standalone)").matches) return
    if (await installDismissed()) return
    const visits = await visitCount()
    if (visits < this.minVisitsValue) return
    this.bannerTarget.hidden = false
  }

  async install(event) {
    event.preventDefault()
    if (!this.deferredPrompt) return
    await this.deferredPrompt.prompt()
    await this.deferredPrompt.userChoice
    this.deferredPrompt = null
    this.#hideBanner()
  }

  async dismiss(event) {
    event.preventDefault()
    await dismissInstall()
    this.#hideBanner()
  }
}