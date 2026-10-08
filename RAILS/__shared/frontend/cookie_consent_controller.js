import { Controller } from "@hotwired/stimulus"
import { PURPOSES, readConsent, saveConsent } from "pub4/cookie_consent"

export default class extends Controller {
  static targets = [ "banner", "preferences", "analytics", "advertising" ]

  connect() {
    this.applyExistingChoices()
    if (!readConsent()) this.showBanner(false)
  }

  open() {
    this.applyExistingChoices()
    this.showBanner(true)
  }

  showBanner(showPreferences) {
    this.bannerTarget.hidden = false
    this.preferencesTarget.hidden = !showPreferences
    if (showPreferences) this.preferencesTarget.querySelector("input")?.focus()
  }

  manage() {
    this.applyExistingChoices()
    this.preferencesTarget.hidden = false
    this.preferencesTarget.querySelector("input")?.focus()
  }

  accept() {
    this.persist(PURPOSES)
  }

  reject() {
    this.persist([])
  }

  save() {
    const selected = []
    if (this.analyticsTarget.checked) selected.push("analytics")
    if (this.advertisingTarget.checked) selected.push("advertising")
    this.persist(selected)
  }

  close() {
    this.reject()
  }

  applyExistingChoices() {
    const purposes = readConsent()?.purposes || []
    this.analyticsTarget.checked = purposes.includes("analytics")
    this.advertisingTarget.checked = purposes.includes("advertising")
  }

  persist(purposes) {
    saveConsent(purposes)
    this.bannerTarget.hidden = true
    this.preferencesTarget.hidden = true
  }
}