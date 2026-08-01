import { Controller } from "@hotwired/stimulus"

// Typing ping + chat composer affordances (Enter sends, Shift+Enter newline).
// Shared by channel, DM, and any form that opts in via typing-input.
export default class extends Controller {
  static values = { url: String }

  connect() {
    this.lastPing = 0
  }

  ping() {
    if (!this.hasUrlValue || !this.urlValue) return
    const now = Date.now()
    if (now - this.lastPing < 2000) return
    this.lastPing = now
    fetch(this.urlValue, {
      method: "POST",
      headers: { "X-CSRF-Token": this.csrf, "Accept": "text/vnd.turbo-stream.html" }
    })
  }

  // Enter sends; Shift+Enter keeps a newline (same as the corner dock).
  composerKeydown(event) {
    if (event.key !== "Enter" || event.shiftKey) return
    if (event.isComposing) return
    event.preventDefault()
    const form = event.target.closest("form") || this.element
    if (!(form instanceof HTMLFormElement)) return
    if (typeof form.requestSubmit === "function") form.requestSubmit()
    else form.dispatchEvent(new Event("submit", { bubbles: true, cancelable: true }))
  }

  get csrf() {
    return document.querySelector("meta[name=csrf-token]")?.content || ""
  }
}
