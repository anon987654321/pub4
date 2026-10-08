import { Controller } from "@hotwired/stimulus"
import { allows } from "pub4/cookie_consent"

export default class extends Controller {
  static values = { src: String, epi: String }

  connect() {
    this.onConsent = () => this.loadIfAllowed()
    window.addEventListener("pub4:cookie-consent-resolved", this.onConsent)
    this.loadIfAllowed()
  }

  disconnect() {
    window.removeEventListener("pub4:cookie-consent-resolved", this.onConsent)
  }

  loadIfAllowed() {
    if (this.loaded || !allows("advertising") || !this.srcValue) return

    const init = () => {
      const epi = this.parseEpi()
      if (epi) window.tdlc_epi = epi
      if (typeof window.TDLinkConverter !== "undefined") {
        window.TDLinkConverter.init({ tdlc_epi: window.tdlc_epi })
      }
    }

    window.tdlcAsyncInit = init

    const existing = document.getElementById("td-link-converter")
    if (existing) {
      init()
      this.loaded = true
      return
    }

    const script = document.createElement("script")
    script.id = "td-link-converter"
    script.async = true
    script.src = this.srcValue
    script.onload = () => {
      init()
      this.loaded = true
    }
    document.head.appendChild(script)
  }

  parseEpi() {
    if (!this.epiValue) return null
    try { return JSON.parse(this.epiValue) } catch (_) { return null }
  }
}