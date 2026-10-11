import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["status"]
  static values = { url: String }

  locate() {
    if (!("geolocation" in navigator)) {
      this.statusTarget.textContent = "This browser does not provide location access."
      return
    }

    this.statusTarget.textContent = "Waiting for your permission…"
    navigator.geolocation.getCurrentPosition(
      (position) => this.submitLocation(position),
      () => {
        this.statusTarget.textContent = "Location was not shared. Check your browser permission and try again."
      },
      { enableHighAccuracy: false, maximumAge: 30000, timeout: 10000 }
    )
  }

  async submitLocation(position) {
    const token = document.querySelector('meta[name="csrf-token"]')?.content
    if (!token) {
      this.statusTarget.textContent = "The secure request token is missing. Reload this page and try again."
      return
    }

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
      if (!response.ok) {
        this.statusTarget.textContent = response.status === 429
          ? "You have checked recently. Try again in a few minutes."
          : "No location was saved. Check your profile visibility and verification status."
        return
      }

      this.statusTarget.textContent = "Location shared approximately for five minutes. Refreshing the recent crossings…"
      window.location.reload()
    } catch {
      this.statusTarget.textContent = "The location request failed. Nothing was confirmed as saved."
    }
  }
}
