import { Controller } from "@hotwired/stimulus"

// Typing ping + chat composer affordances (Enter sends, Shift+Enter newline,
// empty-send disabled). Shared by channel, DM, and the corner dock.
export default class extends Controller {
  static values = { url: String }

  connect() {
    this.lastPing = 0
    this.field = this.element.querySelector("textarea, input[type=text]")
    this.submit = this.element.querySelector("[type=submit]")
    this.#syncSubmit()
    this.onInput = () => this.#syncSubmit()
    this.field?.addEventListener("input", this.onInput)
  }

  disconnect() {
    this.field?.removeEventListener("input", this.onInput)
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
    if (!this.#hasContent()) {
      event.preventDefault()
      return
    }
    event.preventDefault()
    const form = event.target.closest("form") || this.element
    if (!(form instanceof HTMLFormElement)) return
    if (typeof form.requestSubmit === "function") form.requestSubmit()
    else form.dispatchEvent(new Event("submit", { bubbles: true, cancelable: true }))
  }

  // Successful chat send counts as install-value (channel, DM, dock).
  markValue(event) {
    if (event?.detail?.success === false) return
    window.dispatchEvent(new CustomEvent("pub4:install-value"))
  }

  #syncSubmit() {
    if (!this.submit) return
    this.submit.disabled = !this.#hasContent()
  }

  #hasContent() {
    return (this.field?.value || "").trim().length > 0
  }

  get csrf() {
    return document.querySelector("meta[name=csrf-token]")?.content || ""
  }
}
