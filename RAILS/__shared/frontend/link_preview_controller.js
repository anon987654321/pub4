import { Controller } from "@hotwired/stimulus"

// Shows the player a pasted link will become while the post is still being
// written. The text field (or the rich-text editor, which echoes its content
// into the field and fires input) is scanned for the first link; the server
// answers with the same shared/_link_embed facade the post will carry, or with
// nothing for a link no provider recognises. Nothing a provider sent is
// inserted: the answer is this app's own partial.
const URL = /https?:\/\/[^\s<>"']+/
const WAIT_MS = 500

export default class extends Controller {
  static targets = ["preview"]
  static values = { url: { type: String, default: "/link_previews" } }

  disconnect() {
    clearTimeout(this.timer)
    this.request?.abort()
  }

  scan(event) {
    clearTimeout(this.timer)
    const text = event.target.value ?? event.target.textContent ?? ""
    this.timer = setTimeout(() => this.#show(text.match(URL)?.[0]), WAIT_MS)
  }

  async #show(link) {
    if (link === this.shown) return
    this.shown = link
    this.request?.abort()
    if (!link) return this.#clear()

    this.request = new AbortController()
    try {
      const response = await fetch(`${this.urlValue}?url=${encodeURIComponent(link)}`, {
        headers: { Accept: "text/html" },
        signal: this.request.signal
      })
      if (response.status !== 200) return this.#clear()
      this.previewTarget.innerHTML = await response.text()
    } catch (error) {
      if (error.name !== "AbortError") this.#clear()
    }
  }

  #clear() {
    this.previewTarget.replaceChildren()
  }
}
