// X-style action controller for brgen subapps
// Handles optimistic updates for likes, reposts, saves, votes etc.
// Matches x.com interaction patterns (hover accent, live counts)

import { Controller } from "@hotwired/stimulus"

const DEBOUNCE_MS = 300

export default class extends Controller {
  static targets = ["count"]
  static values = {
    url: String,
    targetGid: String,
    kind: String,
    count: Number,
    activeClass: { type: String, default: "active" }
  }

  connect() {
    this.originalCount = this.countValue || 0
    this.busy = false
    this.lastToggleAt = 0
  }

  toggle(event) {
    event.preventDefault()

    const now = Date.now()
    if (this.busy || now - this.lastToggleAt < DEBOUNCE_MS) return
    this.lastToggleAt = now

    this._performToggle(event)
  }

  _performToggle(event) {
    const btn = event.currentTarget || this.element
    const isActive = btn.classList.contains(this.activeClassValue)

    btn.classList.toggle(this.activeClassValue, !isActive)

    if (this.hasCountTarget) {
      const delta = isActive ? -1 : 1
      this.countValue = (this.countValue || 0) + delta
      this.countTarget.textContent = this.countValue
    }

    if (!this.urlValue) return

    this.busy = true
    btn.setAttribute("aria-busy", "true")

    const headers = {
      "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content || "",
      "Accept": "text/vnd.turbo-stream.html, application/json"
    }

    const body = this._requestBody()
    if (body) {
      headers["Content-Type"] = "application/x-www-form-urlencoded"
    }

    fetch(this.urlValue, {
      method: "POST",
      headers,
      body,
      credentials: "same-origin"
    }).then(res => {
      if (!res.ok) this._rollback(btn, isActive)
    }).catch(() => this._rollback(btn, isActive))
      .finally(() => {
        this.busy = false
        btn.removeAttribute("aria-busy")
      })
  }

  _requestBody() {
    if (!this.hasTargetGidValue || !this.hasKindValue) return undefined

    return new URLSearchParams({
      target_gid: this.targetGidValue,
      kind: this.kindValue
    })
  }

  _rollback(btn, wasActive) {
    btn.classList.toggle(this.activeClassValue, wasActive)
    if (this.hasCountTarget) {
      this.countValue = this.originalCount
      this.countTarget.textContent = this.originalCount
    }
  }
}