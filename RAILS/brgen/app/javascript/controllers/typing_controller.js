import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { conversationId: Number }

  connect() {
    this.timer = setInterval(() => this.expire(), 6000)
  }

  disconnect() {
    clearInterval(this.timer)
  }

  expire() {
    if (!this.element.childNodes.length) return
    this.element.replaceChildren()
  }
}
