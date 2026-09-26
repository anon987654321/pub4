import { Controller } from "@hotwired/stimulus"
import { VisualField } from "pub4/visual_field"

export default class extends Controller {
  static values = { surface: String }

  connect() {
    this.canvas = document.createElement("canvas")
    this.canvas.className = "pub4-visual-field"
    this.canvas.setAttribute("aria-hidden", "true")
    this.canvas.style.cssText = [
      "position:fixed",
      "inset:0",
      "width:100%",
      "height:100%",
      "pointer-events:none",
      "z-index:0",
      "opacity:.8"
    ].join(";")
    document.body.appendChild(this.canvas)

    this.surface = this.detectSurface()
    this.field = new VisualField({ canvas: this.canvas, surface: this.surface })

    this.pointerMove = (event) => {
      this.field.pointer(
        event.clientX / Math.max(1, window.innerWidth),
        event.clientY / Math.max(1, window.innerHeight),
        true
      )
      this.ensureFrame()
    }
    this.pointerLeave = () => this.field.pointer(this.field.pointerX, this.field.pointerY, false)

    this.visualSignal = (event) => {
      const detail = event.detail || {}
      this.field.signal(detail)
      this.ensureFrame()
    }

    this.visibility = () => {
      if (document.hidden) {
        cancelAnimationFrame(this.raf)
        return
      }
      this.field.last = performance.now()
      this.ensureFrame()
    }

    this.resize = () => {
      this.field.resize()
      this.ensureFrame()
    }

    window.addEventListener("pointermove", this.pointerMove, { passive: true })
    window.addEventListener("pointerleave", this.pointerLeave, { passive: true })
    window.addEventListener("master:visual", this.visualSignal)
    window.addEventListener("master:emotion", this.visualSignal)
    window.addEventListener("pub4:visual", this.visualSignal)
    window.addEventListener("amber:wardrobe-change", this.visualSignal)
    window.addEventListener("radio:audio", this.visualSignal)
    document.addEventListener("visibilitychange", this.visibility)
    window.addEventListener("resize", this.resize, { passive: true })

    this.ensureFrame()
    document.documentElement.dataset.pub4VisualSurface = this.surface
  }

  detectSurface() {
    if (this.surfaceValue) return this.surfaceValue
    if (document.querySelector(".radio-tunnel")) return "radio"
    if (document.body.classList.contains("vertical-dating")) return "dating"
    if (document.body.dataset.surface === "luxury") return "luxury"
    if (window.location.pathname.startsWith("/chat")) return "master"
    return "social"
  }

  ensureFrame() {
    if (this.raf || document.hidden) return
    if (this.field?.reducedMotion) {
      this.field.frame(performance.now())
      return
    }
    this.raf = requestAnimationFrame((now) => {
      this.raf = 0
      if (document.hidden) return
      this.field.frame(now)
      this.ensureFrame()
    })
  }

  disconnect() {
    window.removeEventListener("pointermove", this.pointerMove)
    window.removeEventListener("pointerleave", this.pointerLeave)
    window.removeEventListener("master:visual", this.visualSignal)
    window.removeEventListener("master:emotion", this.visualSignal)
    window.removeEventListener("pub4:visual", this.visualSignal)
    window.removeEventListener("amber:wardrobe-change", this.visualSignal)
    window.removeEventListener("radio:audio", this.visualSignal)
    document.removeEventListener("visibilitychange", this.visibility)
    window.removeEventListener("resize", this.resize)
    cancelAnimationFrame(this.raf)
    this.field?.destroy()
    this.canvas?.remove()
  }
}
