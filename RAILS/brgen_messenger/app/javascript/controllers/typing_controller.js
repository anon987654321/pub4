import { Controller } from "@hotwired/stimulus"

// The broadcast carries a hidden line per kind of viewer (typing_lines_tag):
// one with no data-except for anyone not typing, and one per typer that leaves
// that typer out. The viewer's own line wins; otherwise the general one shows.
export default class extends Controller {
  static values = { conversationId: Number, viewer: Number }
  static targets = ["line"]

  connect() {
    this.timer = setInterval(() => this.expire(), 6000)
  }

  disconnect() {
    clearInterval(this.timer)
  }

  lineTargetConnected() {
    const own = this.lineTargets.find((line) => line.dataset.except === String(this.viewerValue))
    const shown = own || this.lineTargets.find((line) => !line.dataset.except)
    this.lineTargets.forEach((line) => { line.hidden = line !== shown })
  }

  expire() {
    if (!this.element.childNodes.length) return
    this.element.replaceChildren()
  }
}
