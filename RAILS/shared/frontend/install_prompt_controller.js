import { Controller } from "@hotwired/stimulus"
import { installDismissedKey } from "pub4/pwa_standalone"
import { announceInstallVisible } from "pub4/onboarding"

// The unscoped key stays readable so a dismissal from before the key was
// namespaced still counts; only new writes are scoped.
const LEGACY_DISMISSED_KEY = "install-prompt-dismissed"

// Show once Chrome fires beforeinstallprompt, or on iOS where that event
// never exists. A first visit that only reads is still a visit that can
// install — waiting for a post/play/chat meant the banner never appeared
// for someone opening brgen.no on a phone.
export default class extends Controller {
  static targets = [ "body", "installButton" ]
  static values = { iosSafari: String, iosChrome: String }

  connect() {
    this.deferredPrompt = null

    this.onBeforeInstall = (event) => {
      event.preventDefault()
      this.deferredPrompt = event
      this.reveal()
    }

    window.addEventListener("beforeinstallprompt", this.onBeforeInstall)
    this.prepareIosCopy()
    this.reveal()
  }

  disconnect() {
    window.removeEventListener("beforeinstallprompt", this.onBeforeInstall)
  }

  canShow() {
    return !this.dismissed() && (this.deferredPrompt || this.iosManual())
  }

  iosManual() {
    return this.ios() && !this.standalone()
  }

  ios() {
    const ua = navigator.userAgent || ""
    return /iPad|iPhone|iPod/.test(ua) ||
      (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1)
  }

  standalone() {
    return Boolean(window.navigator.standalone) ||
      window.matchMedia("(display-mode: standalone)").matches
  }

  chromeIos() {
    return /CriOS/i.test(navigator.userAgent || "")
  }

  prepareIosCopy() {
    if (!this.iosManual()) return

    const copy = this.chromeIos() ? this.iosChromeValue : this.iosSafariValue
    if (copy && this.hasBodyTarget) this.bodyTarget.textContent = copy
    if (this.hasInstallButtonTarget) this.installButtonTarget.hidden = true
  }

  dismissed() {
    return [installDismissedKey(), LEGACY_DISMISSED_KEY].some(key => localStorage.getItem(key) === "1")
  }

  reveal() {
    if (!this.canShow()) return
    if (!this.element.hidden) return

    this.element.hidden = false
    // Install outranks the menu coach and the push button, and it can appear at
    // any moment. Whichever of the other two is already open steps back rather
    // than stacking.
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
