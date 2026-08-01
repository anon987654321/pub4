import { Controller } from "@hotwired/stimulus"

// Explicit "Use location" control (Nearby page, Live). Dispatches the same
// event the corner chat uses; geolocation_controller handles the prompt + PATCH.
// When reload is true (default), a successful locate refreshes the page so
// server-rendered "located" branches paint.
export default class extends Controller {
  static values = { reload: { type: Boolean, default: true } }

  connect() {
    if (!this.reloadValue) return
    this.onLocated = () => { window.location.reload() }
    window.addEventListener("brgen:located", this.onLocated)
  }

  disconnect() {
    if (this.onLocated) window.removeEventListener("brgen:located", this.onLocated)
  }

  request(event) {
    event?.preventDefault()
    window.dispatchEvent(new CustomEvent("brgen:request-location"))
  }
}
