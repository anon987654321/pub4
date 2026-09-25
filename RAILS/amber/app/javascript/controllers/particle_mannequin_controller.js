import { Controller } from "@hotwired/stimulus"

const WIDTH = 160
const HEIGHT = 390
const COUNT = 520

export default class extends Controller {
  // count: how many particles make the body. opacity: when set, every
  // particle at that alpha instead of fading toward the edges, for a page
  // that draws the figure in a pale ink on white.
  static values = { count: { type: Number, default: COUNT }, opacity: Number }

  connect() {
    this.canvas = document.createElement("canvas")
    this.canvas.className = "mannequin-particles"
    this.canvas.setAttribute("aria-hidden", "true")
    this.element.prepend(this.canvas)

    this.ctx = this.canvas.getContext("2d", { alpha: true })
    this.reducedMotion = window.matchMedia?.("(prefers-reduced-motion: reduce)")?.matches ?? false
    this.points = []
    this.activity = 0.12
    this.pointerX = 0.5
    this.pointerY = 0.42
    this.last = performance.now()

    this.resize = () => {
      const d = Math.min(window.devicePixelRatio || 1, 2)
      this.width = this.canvas.clientWidth || WIDTH
      this.height = this.canvas.clientHeight || HEIGHT
      this.canvas.width = Math.max(1, Math.round(this.width * d))
      this.canvas.height = Math.max(1, Math.round(this.height * d))
      this.ctx.setTransform(d, 0, 0, d, 0, 0)
      this.points = this.seed()
      if (this.reducedMotion) this.draw(performance.now())
    }

    this.pointerMove = (event) => {
      const rect = this.element.getBoundingClientRect()
      this.pointerX = Math.max(0, Math.min(1, (event.clientX - rect.left) / rect.width))
      this.pointerY = Math.max(0, Math.min(1, (event.clientY - rect.top) / rect.height))
      this.activity = Math.min(1, this.activity + 0.08)
    }

    this.wardrobeChange = () => {
      this.activity = Math.min(1, this.activity + 0.18)
    }

    this.element.addEventListener("pointermove", this.pointerMove, { passive: true })
    this.element.addEventListener("amber:wardrobe-change", this.wardrobeChange)
    window.addEventListener("resize", this.resize, { passive: true })
    this.resize()
    this.draw(performance.now())
  }

  disconnect() {
    this.element.removeEventListener("pointermove", this.pointerMove)
    this.element.removeEventListener("amber:wardrobe-change", this.wardrobeChange)
    window.removeEventListener("resize", this.resize)
    this.canvas?.remove()
  }

  seed() {
    const points = []
    for (let i = 0; i < this.countValue; i++) {
      const home = this.bodyPoint()
      points.push({
        // Under reduced motion the figure is drawn once, so it starts formed.
        x: this.reducedMotion ? home.x * this.width / WIDTH : Math.random() * this.width,
        y: this.reducedMotion ? home.y * this.height / HEIGHT : Math.random() * this.height,
        vx: (Math.random() - 0.5) * 0.3,
        vy: (Math.random() - 0.5) * 0.3,
        homeX: home.x,
        homeY: home.y,
        size: 0.7 + Math.random() * 1.1,
        phase: Math.random() * Math.PI * 2
      })
    }
    return points
  }

  bodyPoint() {
    const x = Math.random() * WIDTH
    const y = Math.random() * HEIGHT

    const head = ((x - 80) ** 2) / (27 ** 2) + ((y - 34) ** 2) / (31 ** 2) < 1
    const neck = x >= 73 && x <= 87 && y >= 62 && y <= 82
    const torso = y >= 75 && y <= 205 && x >= 10 && x <= 150 && this.shoulderWidth(x, y)
    const pelvis = y >= 195 && y <= 258 && x >= 6 && x <= 154 && Math.abs(x - 80) < 75
    const leftLeg = y >= 235 && y <= 373 && x >= 2 && x <= 80 && x < 78 - (y - 235) * 0.18
    const rightLeg = y >= 235 && y <= 373 && x >= 80 && x <= 158 && x > 82 + (y - 235) * 0.18
    const leftFoot = y >= 368 && y <= 388 && x <= 55
    const rightFoot = y >= 368 && y <= 388 && x >= 105

    if (head || neck || torso || pelvis || leftLeg || rightLeg || leftFoot || rightFoot) {
      return { x, y }
    }

    return this.bodyPoint()
  }

  shoulderWidth(x, y) {
    const shoulder = 28 + Math.max(0, y - 82) * 0.35
    return Math.abs(x - 80) < shoulder
  }

  draw(now) {
    if (!this.ctx) return

    const dt = Math.min(0.04, (now - this.last) / 1000)
    this.last = now
    this.activity += (0.12 - this.activity) * dt * 0.7

    this.ctx.clearRect(0, 0, this.width, this.height)

    // --particle-ink lets a page paint the figure its own colour (the home
    // page's looks draw it in their grey); elsewhere it is the accent.
    const accent = getComputedStyle(this.element).getPropertyValue("--particle-ink").trim() ||
      getComputedStyle(document.documentElement).getPropertyValue("--accent").trim() || "#667085"

    const centerX = this.width * 0.5
    const centerY = this.height * 0.43
    const pointerX = this.width * this.pointerX
    const pointerY = this.height * this.pointerY

    this.points.forEach((point) => {
      const scaleX = this.width / WIDTH
      const scaleY = this.height / HEIGHT
      const homeX = point.homeX * scaleX
      const homeY = point.homeY * scaleY
      const homeDx = homeX - point.x
      const homeDy = homeY - point.y

      point.vx += homeDx * 1.2 * dt
      point.vy += homeDy * 1.2 * dt

      const pointerDx = pointerX - point.x
      const pointerDy = pointerY - point.y
      const pointerDistance = Math.max(36, Math.hypot(pointerDx, pointerDy))
      const pointerForce = (0.02 + this.activity * 0.09) / pointerDistance
      point.vx -= pointerDx * pointerForce * dt
      point.vy -= pointerDy * pointerForce * dt

      const drift = Math.sin(now * 0.0014 + point.phase) * (0.25 + this.activity * 0.8)
      point.vx += -homeDy * 0.0008 * drift
      point.vy += homeDx * 0.0008 * drift

      point.vx *= 0.975
      point.vy *= 0.975
      point.x += point.vx * 70 * dt
      point.y += point.vy * 70 * dt

      const edge = Math.hypot(point.x - centerX, point.y - centerY) / Math.max(this.width, this.height)
      this.ctx.globalAlpha = this.opacityValue || Math.max(0.05, 0.58 - edge * 0.36)
      this.ctx.fillStyle = accent
      this.ctx.fillRect(Math.round(point.x), Math.round(point.y), point.size, point.size)
    })

    this.ctx.globalAlpha = 1
    if (!this.reducedMotion) requestAnimationFrame((frame) => this.draw(frame))
  }
}
