import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { radiusKm: { type: Number, default: 2 }, url: String }

  #seen = new Set()
  #watch = null

  connect() {
    if (!navigator.geolocation || !this.hasUrlValue) return
    this.#watch = navigator.geolocation.watchPosition(
      pos => this.#send(pos.coords.latitude, pos.coords.longitude),
      () => {},
      { enableHighAccuracy: true, maximumAge: 30_000, timeout: 10_000 }
    )
  }

  disconnect() {
    if (this.#watch !== null) navigator.geolocation.clearWatch(this.#watch)
  }

  // Called by Turbo Stream when a nearby user is detected server-side.
  // Deduplicates so each stranger only triggers one alert per page session.
  alertArrival(handle, userId) {
    if (this.#seen.has(userId)) return
    this.#seen.add(userId)
  }

  #send(lat, lng) {
    fetch(this.urlValue, {
      method: "PATCH",
      credentials: "same-origin",
      headers: {
        "Accept": "application/json",
        "Content-Type": "application/json",
        "X-CSRF-Token": document.querySelector("meta[name=csrf-token]")?.content
      },
      body: JSON.stringify({ latitude: lat, longitude: lng, radius_km: this.radiusKmValue })
    }).catch(() => {})
  }
}
