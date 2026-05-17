import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { url: String }

  connect() {
    if (!navigator.geolocation) return
    navigator.geolocation.getCurrentPosition(
      pos => this.#send(pos.coords.latitude, pos.coords.longitude),
      () => {}
    )
  }

  #send(lat, lng) {
    fetch(this.urlValue, {
      method: "PATCH",
      headers: { "Content-Type": "application/json", "X-CSRF-Token": document.querySelector("meta[name=csrf-token]")?.content },
      body: JSON.stringify({ latitude: lat, longitude: lng })
    }).then(r => { if (r.ok) this.element.dataset.located = "true" })
  }
}
