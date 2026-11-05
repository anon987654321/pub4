import { Controller } from "@hotwired/stimulus"

// The profile form's username hint. After a pause in typing it asks
// users#username_availability whether the name is free and well formed, and
// writes the answer into a polite live region beside the field, so the person
// learns before saving rather than from the error after. The server words the
// answer; this only fetches and shows it. The field's own pattern, minlength
// and maxlength still hold the form without JavaScript.
const PAUSE_MS = 350

export default class extends Controller {
  static targets = ["input", "hint"]
  static values = { url: String, current: String }

  disconnect() {
    clearTimeout(this.timer)
    this.request?.abort()
  }

  check() {
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.ask(), PAUSE_MS)
  }

  async ask() {
    const name = this.inputTarget.value.trim()

    if (name === "" || name === this.currentValue) {
      this.show("", null)
      return
    }

    this.request?.abort()
    this.request = new AbortController()

    const url = new URL(this.urlValue, window.location.href)
    url.searchParams.set("username", name)

    try {
      const response = await fetch(url, {
        headers: { Accept: "application/json" },
        signal: this.request.signal,
        credentials: "same-origin"
      })
      if (!response.ok) return
      const answer = await response.json()
      if (this.inputTarget.value.trim() === name) this.show(answer.message, answer.available)
    } catch (error) {
      if (error.name !== "AbortError") this.show("", null)
    }
  }

  show(message, available) {
    const { dataset } = this.hintTarget

    this.hintTarget.textContent = message
    if (available === null) {
      delete dataset.available
    } else {
      dataset.available = String(available)
    }
  }
}
