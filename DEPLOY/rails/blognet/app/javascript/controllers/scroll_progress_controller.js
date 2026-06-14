import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.bar = document.createElement("div")
    this.bar.className = "scroll-progress"
    this.bar.setAttribute("aria-hidden", "true")
    document.body.prepend(this.bar)
    this.update = this.update.bind(this)
    this.update()
    window.addEventListener("scroll", this.update, { passive: true })
    window.addEventListener("resize", this.update)
  }

  disconnect() {
    window.removeEventListener("scroll", this.update)
    window.removeEventListener("resize", this.update)
    this.bar?.remove()
  }

  update() {
    const doc = document.documentElement
    const max = Math.max(1, doc.scrollHeight - window.innerHeight)
    const value = Math.min(1, Math.max(0, window.scrollY / max))
    if (this.bar) this.bar.style.transform = `scaleX(${value})`
  }
}
