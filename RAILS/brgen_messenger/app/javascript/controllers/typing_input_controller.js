import { Controller } from "@hotwired/stimulus"

// Typing ping + chat composer affordances (Enter sends, Shift+Enter newline,
// empty-send disabled). Shared by channel, DM, and the corner dock.
//
// A photo or a voice note is something to send. Send was enabled by text alone,
// so a message the server accepts without a body (Message validates content
// only when nothing is attached) could not be sent from the page.
export default class extends Controller {
  static values = { url: String }

  connect() {
    this.lastPing = 0
    this.field = this.element.querySelector("textarea, input[type=text]")
    this.submit = this.element.querySelector("[type=submit]")
    this.#syncSubmit()
    this.onInput = () => this.#syncSubmit()
    this.field?.addEventListener("input", this.onInput)
    // On the form, not the file field: the picker fires change on it, and the
    // voice recorder dispatches one after it fills the field.
    this.element.addEventListener("change", this.onInput)
  }

  disconnect() {
    this.field?.removeEventListener("input", this.onInput)
    this.element.removeEventListener("change", this.onInput)
  }

  ping() {
    if (!this.hasUrlValue || !this.urlValue) return
    const now = Date.now()
    if (now - this.lastPing < 2000) return
    this.lastPing = now
    fetch(this.urlValue, {
      method: "POST",
      headers: { "X-CSRF-Token": this.csrf, "Accept": "text/vnd.turbo-stream.html" }
    }).catch(() => {})
    // A dead connection drops the ping; the next keystroke inside the window
    // re-fires it, and an unhandled rejection must not stack up meanwhile.
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
    if ((this.field?.value || "").trim().length > 0) return true
    return Array.from(this.element.querySelectorAll("input[type=file]")).some((input) => input.files?.length > 0)
  }

  get csrf() {
    return document.querySelector("meta[name=csrf-token]")?.content ?? ""
  }
}
