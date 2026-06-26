import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { url: String }

  connect() {
    this.lastPing = 0
  }

  ping() {
    const now = Date.now()
    if (now - this.lastPing < 2000) return
    this.lastPing = now
    fetch(this.urlValue, {
      method: "POST",
      headers: { "X-CSRF-Token": this.csrf, "Accept": "text/vnd.turbo-stream.html" }
    })
  }

  get csrf() {
    return document.querySelector("meta[name=csrf-token]")?.content || ""
  }
}
