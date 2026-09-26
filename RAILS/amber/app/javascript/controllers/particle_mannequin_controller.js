import { Controller } from "@hotwired/stimulus"
import { VisualField } from "pub4/visual_field"

export default class extends Controller {
  static values = { count: { type: Number, default: 520 }, opacity: Number }

  connect() {
    this.canvas = document.createElement("canvas")
    this.canvas.className = "mannequin-particles"
    this.canvas.setAttribute("aria-hidden", "true")
    this.element.prepend(this.canvas)

    this.field = new VisualField({
      canvas: this.canvas,
      surface: "mannequin",
      count: this.countValue,
      local: true
    })

    this.pointerMove = (event) => {
      const rect = this.element.getBoundingClientRect()
      this.field.pointer(
        (event.clientX - rect.left) / Math.max(1, rect.width),
        (event.clientY - rect.top) / Math.max(1, rect.height),
        true
      )
      this.field.ensureCount()
    }

    this.wardrobeChange = (event) => {
      this.field.signal({
        name: "amber:wardrobe-change",
        mode: "wardrobe",
        activity: 0.72,
        entropy: 0.16,
        confidence: 0.88,
        valence: 0.22,
        topology: "mannequin"
      })
    }

    this.resize = () => {
      this.field.resize()
    }

    this.visualSignal = (event) => {
      this.field.signal(event.detail || {})
    }

    this.element.addEventListener("pointermove", this.pointerMove, { passive: true })
    this.element.addEventListener("amber:wardrobe-change", this.wardrobeChange)
    window.addEventListener("master:visual", this.visualSignal)
    window.addEventListener("master:emotion", this.visualSignal)
    window.addEventListener("pub4:visual", this.visualSignal)
    window.addEventListener("resize", this.resize, { passive: true })

    document.documentElement.dataset.amberVisual = "mannequin"
  }

  disconnect() {
    this.element.removeEventListener("pointermove", this.pointerMove)
    this.element.removeEventListener("amber:wardrobe-change", this.wardrobeChange)
    window.removeEventListener("master:visual", this.visualSignal)
    window.removeEventListener("master:emotion", this.visualSignal)
    window.removeEventListener("pub4:visual", this.visualSignal)
    window.removeEventListener("resize", this.resize)
    this.field?.destroy()
    this.canvas?.remove()
  }
}
