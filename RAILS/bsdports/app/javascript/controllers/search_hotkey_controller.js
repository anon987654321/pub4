import { Controller } from "@hotwired/stimulus"

// Keyboard-first package research: / and Cmd/Ctrl-K focus the primary search.
export default class extends Controller {
  static targets = ["input"]

  connect() {
    this.keydown = this.keydown.bind(this)
    window.addEventListener("keydown", this.keydown)
  }

  disconnect() {
    window.removeEventListener("keydown", this.keydown)
  }

  keydown(event) {
    const editable = event.target.matches("input, textarea, select, [contenteditable=true]")
    const shortcut = event.key === "/" || ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "k")
    if (!shortcut || (editable && event.key === "/")) return

    event.preventDefault()
    const input = this.inputTarget.querySelector("input") || this.inputTarget
    input.focus()
    input.select?.()
  }
}
