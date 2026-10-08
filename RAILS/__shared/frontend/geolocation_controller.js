import { Controller } from "@hotwired/stimulus"

// Shared, battery- and visibility-aware geolocation controller.
// Works for both brgen and amber.
//
// Events:
//   pub4:located / brgen:located
//   pub4:location-error / brgen:location-error
//
export default class extends Controller {
  static values = {
    radiusKm: { type: Number, default: 2 },
    url: String,
    highAccuracy: { type: Boolean, default: true }
  }

  #seen = new Set()
  #watch = null
  located = false
  #batteryLow = false

  connect() {
    this.onRequest = () => this.prompt()
    window.addEventListener("pub4:request-location", this.onRequest)
    window.addEventListener("brgen:request-location", this.onRequest)

    document.addEventListener("visibilitychange", this.#onVisibility)
    window.addEventListener("pub4:battery-change", this.#onBatteryChange)
    window.addEventListener("pub4:visibility-change", this.#onVisibilityChange)

    if (!navigator.geolocation || !this.hasUrlValue) return
    // Skip when document Permissions-Policy denies geolocation (no console spam).
    try {
      if (document.featurePolicy?.allowsFeature && !document.featurePolicy.allowsFeature("geolocation")) {
        this.#announceError("blocked")
        return
      }
    } catch (_) { /* older browsers */ }

    this.#startWatch()
  }

  disconnect() {
    window.removeEventListener("pub4:request-location", this.onRequest)
    window.removeEventListener("brgen:request-location", this.onRequest)
    document.removeEventListener("visibilitychange", this.#onVisibility)
    window.removeEventListener("pub4:battery-change", this.#onBatteryChange)
    window.removeEventListener("pub4:visibility-change", this.#onVisibilityChange)
    this.#stopWatch()
  }

  prompt() {
    if (!navigator.geolocation) {
      this.#announceError("unavailable")
      return
    }

    try {
      if (localStorage.getItem("pub4:location-denied") === "1") {
        this.#announceError("denied")
        return
      }
    } catch (_) { /* private mode */ }

    navigator.geolocation.getCurrentPosition(
      pos => this.#send(pos.coords),
      err => this.#onError(err),
      { enableHighAccuracy: this.highAccuracyValue, timeout: 12_000, maximumAge: 60_000 }
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
      err => this.#onError(err),
      { enableHighAccuracy: this.highAccuracyValue, timeout: 10_000 }
    )
  }

  // Called by Turbo Stream when a nearby user is detected server-side.
  // Deduplicates so each stranger only triggers one alert per page session.
  alertArrival(handle, userId) {
    if (this.#seen.has(userId)) return
    this.#seen.add(userId)
  }

  #startWatch() {
    if (document.hidden || this.#batteryLow) {
      this.#stopWatch()
      return
    }
    if (this.#watch !== null) return

    try {
      this.#watch = navigator.geolocation.watchPosition(
        pos => this.#send(pos.coords),
        err => this.#onError(err),
        {
          enableHighAccuracy: this.highAccuracyValue && !this.#batteryLow,
          maximumAge: 45_000,
          timeout: 15_000
        }
      )
    } catch (_) {
      this.#announceError("blocked")
    }
  }

  #stopWatch() {
    if (this.#watch !== null) {
      navigator.geolocation.clearWatch(this.#watch)
      this.#watch = null
    }
  }

  #onVisibility = () => this.#reconcileWatch()
  #onVisibilityChange = () => this.#reconcileWatch()

  #onBatteryChange = (event) => {
    this.#batteryLow = !!event.detail?.low
    this.#reconcileWatch()
  }

  #reconcileWatch() {
    if (document.hidden || this.#batteryLow) {
      this.#stopWatch()
    } else if (this.hasUrlValue) {
      this.#startWatch()
    }
  }

  #send({ latitude, longitude, accuracy }) {
    if (!this.hasUrlValue) return
    fetch(this.urlValue, {
      method: "PATCH",
      credentials: "same-origin",
      headers: {
        "Accept": "application/json",
        "Content-Type": "application/json",
        "X-CSRF-Token": document.querySelector("meta[name=csrf-token]")?.content
      },
      body: JSON.stringify({
        latitude,
        longitude,
        accuracy,
        radius_km: this.radiusKmValue
      })
    }).then(res => {
      // Only announce after the server actually stored coordinates. A 4xx/5xx
      // used to still fire brgen:located, reloading the nearby widget into the
      // same "Share location" dead end.
      if (res.ok) this.#announceLocated()
      else this.#announceError("server")
    }).catch(() => this.#announceError("network"))
  }

  #onError(err) {
    if (err?.code === 1) {
      try { localStorage.setItem("pub4:location-denied", "1") } catch (_) { /* private mode */ }
      this.#announceError("denied")
    } else if (err?.code === 3) {
      this.#announceError("timeout")
    } else {
      this.#announceError("unavailable")
    }
  }

  #announceLocated() {
    if (this.located) return
    this.located = true
    window.dispatchEvent(new CustomEvent("pub4:located"))
    window.dispatchEvent(new CustomEvent("brgen:located"))
  }

  #announceError(reason) {
    window.dispatchEvent(new CustomEvent("pub4:location-error", { detail: { reason } }))
    window.dispatchEvent(new CustomEvent("brgen:location-error", { detail: { reason } }))
  }
}
