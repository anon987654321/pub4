import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input"]
  static values = { delay: { type: Number, default: 300 } }

  connect() {
    this.timeout = null
  }

  disconnect() {
    clearTimeout(this.timeout)
  }

  input() {
    clearTimeout(this.timeout)
    this.timeout = setTimeout(() => this.submitForm(), this.delayValue)
  }

  submitForm() {
    const form = this.element.querySelector("form")
    if (!form) return
    form.requestSubmit()
  }
}