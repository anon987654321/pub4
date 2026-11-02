import { Controller } from "@hotwired/stimulus"

// Live tracking (§8): polls GET /track/:token/status (json: { state, eta,
// updated_at }) every 10s, swaps the eta line, and reloads the page on state
// change so the server-rendered timeline stays authoritative.
export default class extends Controller {
  static targets = ["steps", "eta"]
  static values = {
    token: String,
    state: String,
    etaTemplate: String,
    interval: { type: Number, defaultValue: 10000 },
  }

  connect() {
    this.timer = setInterval(() => this.poll(), this.intervalValue)
  }

  disconnect() {
    clearInterval(this.timer)
  }

  poll() {
    fetch(`/track/${encodeURIComponent(this.tokenValue)}/status`, {
      headers: { Accept: "application/json" },
    })
      .then((response) => (response.ok ? response.json() : null))
      .then((data) => {
        if (!data) return
        if (data.state && data.state !== this.stateValue) {
          location.reload()
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
}
