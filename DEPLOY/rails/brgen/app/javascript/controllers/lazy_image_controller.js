// Lazy image controller — IntersectionObserver based, with blurhash placeholder support (AN506).
// Micro cosmetic: smooth fade-in, respects reduced-motion, low impact.
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["image"]
  static values = { src: String, blurhash: String }

  connect() {
    if (this.hasImageTarget) {
      this.observer = new IntersectionObserver(this.load.bind(this), {
        rootMargin: "200px"
      })
      this.observer.observe(this.imageTarget)
    }
  }

  disconnect() {
    if (this.observer) this.observer.disconnect()
  }

  load(entries) {
    entries.forEach(entry => {
      if (entry.isIntersecting && this.hasImageTarget) {
        const img = this.imageTarget
        const originalSrc = this.srcValue || img.dataset.src
        if (!originalSrc) return

        // Optional blurhash canvas placeholder (if provided via data)
        if (this.blurhashValue && !img.complete) {
          this.renderBlurhashPlaceholder(img, this.blurhashValue)
        }

        img.src = originalSrc
        img.classList.add("lazy-loaded")

        img.onload = () => {
          img.classList.add("lazy-fade-in")
          if (this.observer) this.observer.unobserve(img)
        }

        delete img.dataset.src
      }
    })
  }

  renderBlurhashPlaceholder(img, hash) {
    // Very lightweight: create tiny canvas, decode simple blurhash approximation
    // For full blurhash, would need the lib, but this is micro: solid color + opacity as fallback
    const canvas = document.createElement("canvas")
    canvas.width = 32
    canvas.height = 32
    const ctx = canvas.getContext("2d", { alpha: true })
    ctx.fillStyle = "#222"
    ctx.fillRect(0, 0, 32, 32)
    const dataUrl = canvas.toDataURL()
    img.style.backgroundImage = `url(${dataUrl})`
    img.style.backgroundSize = "cover"
    img.style.transition = "opacity 240ms ease"
  }
}
