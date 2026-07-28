import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { radiusKm: { type: Number, default: 2 }, url: String }

  #seen = new Set()
  #watch = null

  connect() {
    // Anything that needs coordinates can ask for them without knowing where
    // this controller lives in the layout.
    this.onRequest = () => this.#prompt()
    window.addEventListener("brgen:request-location", this.onRequest)

    if (!navigator.geolocation || !this.hasUrlValue) return
    // Skip when document Permissions-Policy denies geolocation (no console spam).
    try {
      if (document.featurePolicy?.allowsFeature && !document.featurePolicy.allowsFeature("geolocation")) return
    } catch (_) { /* older browsers */ }

    try {
      this.#watch = navigator.geolocation.watchPosition(
        pos => this.#send(pos.coords.latitude, pos.coords.longitude),
        () => {},
        { enableHighAccuracy: true, maximumAge: 30_000, timeout: 10_000 }
      )
    } catch (_) {
      // SecurityError when policy blocks geolocation
    }
  }

  disconnect() {
    window.removeEventListener("brgen:request-location", this.onRequest)
    if (this.#watch !== null) navigator.geolocation.clearWatch(this.#watch)
  }

  // A one-shot ask, for surfaces that need coordinates on demand. watchPosition
  // in connect() only prompts once per page; if the visitor dismissed it there
  // is otherwise no way back short of browser settings.
  #prompt() {
    if (!navigator.geolocation || !this.hasUrlValue) return

    navigator.geolocation.getCurrentPosition(
      pos => this.#send(pos.coords.latitude, pos.coords.longitude),
      () => {},
      { enableHighAccuracy: true, timeout: 10_000 }
    )
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
    }).then(() => this.#announceLocated()).catch(() => {})
  }

  // Anything server-rendered against "do we know where you are" was rendered
  // before the browser answered that question — the permission prompt resolves
  // after first paint. The nearby chat widget was the visible casualty: its
  // frame rendered "Share location to join", location arrived a second later,
  // and nothing told the frame to reload, so it sat on that dead end for the
  // whole session. Fires once; watchPosition keeps calling #send as you move.
  #announceLocated() {
    if (this.located) return
    this.located = true
    window.dispatchEvent(new CustomEvent("brgen:located"))
  }
}
