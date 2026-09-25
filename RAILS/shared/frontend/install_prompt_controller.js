import { Controller } from "@hotwired/stimulus"
import { installDismissedKey, standalone } from "pub4/pwa_standalone"
import { announceInstallVisible } from "pub4/onboarding"

// The unscoped key stays readable so a dismissal from before the key was
// namespaced still counts; only new writes are scoped.
const LEGACY_DISMISSED_KEY = "install-prompt-dismissed"
const ENGAGEMENT = [ "scroll", "pointerdown", "keydown" ]

// A phone that is not already installed gets asked on the first visit.
// beforeinstallprompt is Chrome's native dialog, not a gate: it often never
// fires on a first sitting, and it never fires on iOS. Waiting for it was
// why opening brgen.no in Chrome on a phone showed nothing.
export default class extends Controller {
  static targets = [ "body", "installButton" ]
  static values = { iosSafari: String, iosChrome: String, android: String, afterEngagement: Boolean }

  connect() {
    this.deferredPrompt = null

    this.onBeforeInstall = (event) => {
      event.preventDefault()
      this.deferredPrompt = event
      if (this.hasInstallButtonTarget) this.installButtonTarget.hidden = false
      this.reveal()
    }

    window.addEventListener("beforeinstallprompt", this.onBeforeInstall)
    this.prepareCopy()

    // afterEngagement: the page's first screen is the page (amber's home is
    // its mark in white, brgen's every surface its content), so the prompt
    // waits for a scroll, a tap or a key.
    this.engaged = !this.afterEngagementValue
    this.onEngage = () => {
      this.engaged = true
      this.stopListening()
      this.reveal()
    }
    if (!this.engaged) {
      for (const type of ENGAGEMENT) window.addEventListener(type, this.onEngage, { once: true, passive: true })
    }
    this.reveal()
  }

  stopListening() {
    for (const type of ENGAGEMENT) window.removeEventListener(type, this.onEngage)
  }

  disconnect() {
    window.removeEventListener("beforeinstallprompt", this.onBeforeInstall)
    this.stopListening()
  }

  canShow() {
    if (this.dismissed() || standalone()) return false

    return this.deferredPrompt || this.ios() || this.phone()
  }

  phone() {
    return window.matchMedia("(pointer: coarse)").matches ||
      window.matchMedia("(max-width: 48rem)").matches
  }

  ios() {
    const ua = navigator.userAgent || ""
    return /iPad|iPhone|iPod/.test(ua) ||
      (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1)
  }

  chromeIos() {
    return /CriOS/i.test(navigator.userAgent || "")
  }

  prepareCopy() {
    if (!this.ios()) return

    const copy = this.chromeIos() ? this.iosChromeValue : this.iosSafariValue
    if (copy && this.hasBodyTarget) this.bodyTarget.textContent = copy
    if (this.hasInstallButtonTarget) this.installButtonTarget.hidden = true
  }

  dismissed() {
    return [installDismissedKey(), LEGACY_DISMISSED_KEY].some(key => {
      try { return localStorage.getItem(key) === "1" } catch (_) { return false }
    })
  }

  reveal() {
    if (!this.engaged || !this.canShow()) return
    if (!this.element.hidden) return

    this.element.hidden = false
    announceInstallVisible()
  }

  dismiss() {
    try { localStorage.setItem(installDismissedKey(), "1") } catch (_) { /* private mode */ }
    this.element.hidden = true
  }

  async install() {
    if (this.deferredPrompt) {
      this.deferredPrompt.prompt()
      await this.deferredPrompt.userChoice
      this.deferredPrompt = null
      this.element.hidden = true
      return
    }

    if (this.hasBodyTarget && this.androidValue) this.bodyTarget.textContent = this.androidValue
  }
}
