// X-style action controller for brgen subapps
// Handles optimistic updates for likes, reposts, saves, votes etc.
// Matches x.com interaction patterns (hover accent, live counts)

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["count"]
  static values = { 
    url: String,
    count: Number,
    activeClass: { type: String, default: "active" }
  }

  connect() {
    this.originalCount = this.countValue || 0
  }

  toggle(event) {
    event.preventDefault()
    const btn = event.currentTarget || this.element
    const isActive = btn.classList.contains(this.activeClassValue)

    btn.classList.toggle(this.activeClassValue, !isActive)

    if (this.hasCountTarget) {
      const delta = isActive ? -1 : 1
      this.countValue = (this.countValue || 0) + delta
      this.countTarget.textContent = this.countValue
    }

    if (this.urlValue) {
      fetch(this.urlValue, {
        method: "POST",
        headers: {
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content || "",
          "Accept": "text/vnd.turbo-stream.html, application/json"
        },
        credentials: "same-origin"
      }).then(res => {
        if (!res.ok) this._rollback(btn, isActive)
      }).catch(() => this._rollback(btn, isActive))
    }
  }

  _rollback(btn, wasActive) {
    btn.classList.toggle(this.activeClassValue, wasActive)
    if (this.hasCountTarget) {
      this.countValue = this.originalCount
      this.countTarget.textContent = this.originalCount
    }
  }
}