// Basic buyer-seller chat Stimulus for marketplace orders (AN613 saved search etc.)
// Uses existing turbo or simple fetch; for full, wire ActionCable.
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "log"]

  connect() {
    this.logTarget.scrollTop = this.logTarget.scrollHeight
  }

  send(e) {
    e.preventDefault()
    const msg = this.inputTarget.value.trim()
    if (!msg) return
    // Stub: append locally, in real post to messages or use reflex
    const div = document.createElement("div")
    div.textContent = `You: ${msg}`
    this.logTarget.appendChild(div)
    this.inputTarget.value = ""
    this.logTarget.scrollTop = this.logTarget.scrollHeight
    // TODO: real send via turbo_stream or cable
  }
}
