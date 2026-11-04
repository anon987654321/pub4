import { Controller } from "@hotwired/stimulus"

// Every status line comes from the page's locale (data-*-value attributes
// filled from dating.location_status.*), so the nb page does not answer in
// English once the button is pressed.
export default class extends Controller {
  static targets = ["status"]

  static values = {
    url: String, unsupported: String, waiting: String, denied: String, tokenMissing: String,
    tooSoon: String, refused: String, saved: String, failed: String
  }

  locate() {
    if (!("geolocation" in navigator)) return this.#say(this.unsupportedValue)

    this.#say(this.waitingValue)
    navigator.geolocation.getCurrentPosition(
      (position) => this.submitLocation(position),
      () => this.#say(this.deniedValue),
      { enableHighAccuracy: false, maximumAge: 30000, timeout: 10000 }
    )
  }

  async submitLocation(position) {
    const token = document.querySelector('meta[name="csrf-token"]')?.content
    if (!token) return this.#say(this.tokenMissingValue)

    try {
      const response = await fetch(this.urlValue, {
        method: "POST",
        credentials: "same-origin",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": token,
          "Accept": "application/json"
        },
        body: JSON.stringify({
          location: {
            latitude: position.coords.latitude,
            longitude: position.coords.longitude
          }
        })
      })
      if (!response.ok) return this.#say(response.status === 429 ? this.tooSoonValue : this.refusedValue)

      this.#say(this.savedValue)
      window.location.reload()
    } catch {
      this.#say(this.failedValue)
    }
  }

  #say(text) {
    this.statusTarget.textContent = text
  }
}
