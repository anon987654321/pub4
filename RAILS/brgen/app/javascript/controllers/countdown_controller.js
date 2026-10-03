import { Controller } from "@hotwired/stimulus"

// Renders a live "~N min" estimate from a target ISO timestamp, ticking
// every 30s. Backs the takeaway order ETA badge so it reflects the order's
// own estimated_ready_at instead of a fixed placeholder string.
export default class extends Controller {
  static values = { targetTime: String }

  connect() {
    this.render()
    this.timer = setInterval(() => this.render(), 30_000)
  }

  disconnect() {
    clearInterval(this.timer)
  }

  render() {
    const remainingMs = new Date(this.targetTimeValue).getTime() - Date.now()
    const minutes = Math.round(remainingMs / 60_000)
    this.element.textContent =
      minutes > 1 ? `Est. delivery — ${minutes} min` : "Arriving any moment"
  }
}
