import { Controller } from "@hotwired/stimulus"

// Reading progress bar for long-form content (articles, posts).
export default class extends Controller {
  static targets = ["bar"]
  static values = { color: { type: String, default: "var(--accent, #1d9bf0)" } }

  connect() {
    this.#update = this.#update.bind(this)
    window.addEventListener("scroll", this.#update, { passive: true })
    this.#update()
  }

  disconnect() {
    window.removeEventListener("scroll", this.#update)
  }

  #update() {
    const doc = document.documentElement
    const scrollTop = doc.scrollTop || document.body.scrollTop
    const height = doc.scrollHeight - doc.clientHeight
    const progress = height > 0 ? Math.min(1, scrollTop / height) : 0

    if (this.hasBarTarget) {
      this.barTarget.style.width = `${(progress * 100).toFixed(1)}%`
      this.barTarget.style.background = this.colorValue
    } else {
      doc.style.setProperty("--scroll-progress", progress.toFixed(4))
    }
  }
}