import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["browserNav", "standaloneNav", "backButton"]
  static classes = ["standalone"]

  connect() {
    this.#applyMode()
    this.#mediaQuery()?.addEventListener("change", this.#applyMode)
  }

  disconnect() {
    this.#mediaQuery()?.removeEventListener("change", this.#applyMode)
  }

  #applyMode = () => {
    const standalone = window.matchMedia("(display-mode: standalone)").matches ||
      window.navigator.standalone === true

    document.documentElement.toggleAttribute("data-pwa-standalone", standalone)
    if (this.hasStandaloneClass) document.body.classList.toggle(this.standaloneClass, standalone)

    if (this.hasBrowserNavTarget) this.browserNavTarget.hidden = standalone
    if (this.hasStandaloneNavTarget) this.standaloneNavTarget.hidden = !standalone
    if (this.hasBackButtonTarget) this.backButtonTarget.hidden = standalone
  }

  #mediaQuery() {
    return window.matchMedia("(display-mode: standalone)")
  }
}