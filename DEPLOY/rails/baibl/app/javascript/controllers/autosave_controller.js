import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["status"]
  static values = { url: String, interval: { type: Number, default: 5000 } }

  connect() {
    this.timer = null
    this.element.addEventListener("input", () => this.scheduleSave())
  }

  scheduleSave() {
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.save(), this.intervalValue)
  }

  async save() {
    const body = new FormData(this.element.closest("form") || this.element)
    await fetch(this.urlValue, { method: "PATCH", body, headers: { "X-CSRF-Token": this.csrfToken } })
    if (this.hasStatusTarget) {
      this.statusTarget.textContent = "Saved"
      setTimeout(() => { this.statusTarget.textContent = "" }, 2000)
    }
  }

  get csrfToken() {
    return document.querySelector("meta[name='csrf-token']")?.content
  }
}