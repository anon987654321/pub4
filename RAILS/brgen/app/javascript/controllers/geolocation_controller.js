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
      if (document.featurePolicy?.allowsFeature && !document.featurePolicy.allowsFeature("geolocation")) {
        this.#announceError("blocked")
        return
      }
    } catch (_) { /* older browsers */ }

    try {
      this.#watch = navigator.geolocation.watchPosition(
        pos => this.#send(pos.coords.latitude, pos.coords.longitude),
        err => this.#onGeoError(err),
        { enableHighAccuracy: true, maximumAge: 30_000, timeout: 10_000 }
      )
    } catch (_) {
      // SecurityError when policy blocks geolocation
      this.#announceError("blocked")
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
    if (!navigator.geolocation || !this.hasUrlValue) {
      this.#announceError("unavailable")
      return
    }
    // Permanent deny: do not re-open the browser dialog on every chat open.
    try {
      if (window.localStorage.getItem("pub4:location-denied") === "1") {
        this.#announceError("denied")
        return
      }
    } catch (_) { /* private mode */ }

    navigator.geolocation.getCurrentPosition(
      pos => this.#send(pos.coords.latitude, pos.coords.longitude),
      err => this.#onGeoError(err),
      { enableHighAccuracy: true, timeout: 10_000 }
    )
  }

  // One-shot fill of a search form's hidden lat/lng, then submit. Dating's
  // watchPosition path needs a URL to persist; marketplace "near me" only
  // wants coordinates on this request.
  pin(event) {
    event?.preventDefault()
    if (!navigator.geolocation) {
      this.#announceError("unavailable")
      return
    }
    navigator.geolocation.getCurrentPosition(
      pos => {
        const form = this.element.form || this.element.closest("form")
        if (!form) return
        const lat = form.querySelector("[name='lat']")
        const lng = form.querySelector("[name='lng']")
        if (lat) lat.value = pos.coords.latitude
        if (lng) lng.value = pos.coords.longitude
        form.requestSubmit()
      },
      err => this.#onGeoError(err),
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
    }).then((response) => {
      // Only open nearby chat after the server actually stored coordinates.
      // A 4xx/5xx used to still fire brgen:located, reloading the widget into
      // the same "Share location" dead end and looking broken.
      if (response.ok) this.#announceLocated()
      else this.#announceError("server")
    }).catch(() => this.#announceError("network"))
  }

  #onGeoError(err) {
    const code = err?.code
    // 1 PERMISSION_DENIED, 2 POSITION_UNAVAILABLE, 3 TIMEOUT
    if (code === 1) this.#announceError("denied")
    else if (code === 3) this.#announceError("timeout")
    else this.#announceError("unavailable")
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

  #announceError(reason) {
    window.dispatchEvent(new CustomEvent("brgen:location-error", { detail: { reason } }))
  }
}
