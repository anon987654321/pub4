import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { mode: { type: String, default: "portrait" } }

  connect() {
    this.#lock()
  }

  disconnect() {
    screen.orientation?.unlock?.()
  }

  async #lock() {
    try {
      await screen.orientation?.lock?.(this.modeValue)
    } catch (_) {
      // iOS / desktop may reject orientation lock outside fullscreen
    }
  }
}