import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["output"]

  connect() {
    this.update = this.update.bind(this)
    this.element.addEventListener("input", this.update)
    this.update()
  }

  disconnect() {
    this.element.removeEventListener("input", this.update)
  }

  update() {
    const text = Array.from(this.element.querySelectorAll("[data-reading-time-source]"))
      .map(field => {
        if (field.tagName === "TRIX-EDITOR") {
          return field.editor?.getDocument?.().toString?.() || field.textContent || ""
        }
        return field.value || field.textContent || ""
      })
      .join(" ")
    const words = text.trim().split(/\s+/).filter(Boolean).length
    const minutes = Math.max(1, Math.ceil(words / 200))
    if (this.hasOutputTarget) this.outputTarget.textContent = `${minutes} min read`
  }
}
