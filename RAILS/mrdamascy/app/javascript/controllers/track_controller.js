import { Controller } from "@hotwired/stimulus"

// Live tracking (§8): polls the status url (json: { state, eta, updated_at })
// every 10s, swaps the eta line, and on a state change makes a Turbo replace
// visit to the page itself, which the layout's refresh morph applies in
// place with the scroll kept, so the server-rendered timeline stays
// authoritative. Polls pause while the tab is hidden and stop once the
// order is delivered or cancelled.
const FINAL_STATES = ["delivered", "cancelled"]

export default class extends Controller {
  static targets = ["steps", "eta"]
  static values = {
    url: String,
    state: String,
    etaTemplate: String,
    interval: { type: Number, defaultValue: 10000 },
  }

  connect() {
    this.onVisibility = () => (document.hidden ? this.stop() : this.start())
    document.addEventListener("visibilitychange", this.onVisibility)
    if (!document.hidden) this.start()
  }

  disconnect() {
    document.removeEventListener("visibilitychange", this.onVisibility)
    this.stop()
  }

  // A refresh morph rewrites the state value in place; polling resumes
  // unless the new state is final.
  stateValueChanged() {
    this.start()
  }

  start() {
    if (this.timer || document.hidden || FINAL_STATES.includes(this.stateValue)) return

    this.timer = setInterval(() => this.poll(), this.intervalValue)
  }

  stop() {
    clearInterval(this.timer)
    this.timer = null
  }

  poll() {
    fetch(this.urlValue, { headers: { Accept: "application/json" } })
      .then((response) => (response.ok ? response.json() : null))
      .then((data) => {
        if (!data) return

        if (data.state && data.state !== this.stateValue) {
          this.stop()
          this.refresh()
          return
        }

        if (this.hasEtaTarget && data.eta != null && this.etaTemplateValue) {
          this.etaTarget.textContent = this.etaTemplateValue
            .split("%{eta}")
            .join(String(data.eta))
        }
      })
      .catch(() => {})
  }

  refresh() {
    if (window.Turbo) {
      window.Turbo.visit(window.location.href, { action: "replace" })
    } else {
      window.location.reload()
    }
  }
}
