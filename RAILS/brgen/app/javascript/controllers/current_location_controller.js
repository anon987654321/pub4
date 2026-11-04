import { Controller } from "@hotwired/stimulus"

// Fills a latitude and longitude pair from the device's position, so a courier
// does not type coordinates. The fields stay editable: a refusal or a device
// without geolocation leaves them to be filled by hand.
export default class extends Controller {
  static targets = ["latitude", "longitude", "status"]
  static values = { locating: String, denied: String }

  fill(event) {
    event?.preventDefault()
    if (!navigator.geolocation) return this.#say(this.deniedValue)

    this.#say(this.locatingValue)
    navigator.geolocation.getCurrentPosition(
      ({ coords }) => {
        this.latitudeTarget.value = coords.latitude.toFixed(6)
        this.longitudeTarget.value = coords.longitude.toFixed(6)
        this.#say("")
      },
      () => this.#say(this.deniedValue),
      { enableHighAccuracy: true, timeout: 10_000, maximumAge: 60_000 }
    )
  }

  #say(text) {
    if (this.hasStatusTarget) this.statusTarget.textContent = text
  }
}
