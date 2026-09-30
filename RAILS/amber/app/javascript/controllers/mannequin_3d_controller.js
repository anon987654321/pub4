import { Controller } from "@hotwired/stimulus"

const BODY = {
  head: { top: 0.08, height: 0.12, width: 0.18, radius: 0.09 },
  top: { top: 0.19, height: 0.29, width: 0.32, radius: 0.28 },
  bottom: { top: 0.48, height: 0.27, width: 0.25, radius: 0.22 },
  shoes: { top: 0.79, height: 0.08, width: 0.18, radius: 0.14 }
}

const ZONE_MAP = {
  head: "head",
  crown: "head",
  eyes: "head",
  ears: "head",
  torso: "top",
  top: "top",
  dress: "top",
  legs: "bottom",
  bottom: "bottom",
  feet: "shoes",
  shoes: "shoes"
}

const clamp = (value, min = 0, max = 1) => Math.max(min, Math.min(max, value))

function hash(index, salt = 0) {
  const value = Math.sin(index * 12.9898 + salt * 78.233) * 43758.5453
  return value - Math.floor(value)
}

export default class extends Controller {
  static values = {
    slides: { type: Object, default: {} },
    zones: { type: Object, default: {} }
  }

  connect() {
    this.canvas = document.createElement("canvas")
    this.canvas.className = "mannequin-3d-canvas"
    this.canvas.setAttribute("aria-hidden", "true")
    this.element.prepend(this.canvas)

    this.context = this.canvas.getContext("2d")
    this.images = new Map()
    this.rotation = 0
    this.targetRotation = 0
    this.pointerActive = false
    this.reducedMotion = window.matchMedia?.("(prefers-reduced-motion: reduce)")?.matches ?? false
    this.points = this.buildPoints()
    this.resizeObserver = new ResizeObserver(() => this.resize())
    this.resizeObserver.observe(this.element)
    this.pointerMove = this.onPointerMove.bind(this)
    this.pointerLeave = () => {
      this.pointerActive = false
      this.targetRotation = 0
    }

    this.element.addEventListener("pointermove", this.pointerMove, { passive: true })
    this.element.addEventListener("pointerleave", this.pointerLeave)
    this.element.addEventListener("amber:mannequin-change", this.onMannequinChange)
    this.element.addEventListener("amber:mannequin-slide", this.onSlide)

    if (this.element.dataset.mannequin3dSlidesValue) this.setSlide(0)
    else this.setItems(this.firstItemsFromZones())

    this.resize()
    this.frame()
  }

  disconnect() {
    this.resizeObserver?.disconnect()
    this.element.removeEventListener("pointermove", this.pointerMove)
    this.element.removeEventListener("pointerleave", this.pointerLeave)
    this.element.removeEventListener("amber:mannequin-change", this.onMannequinChange)
    this.element.removeEventListener("amber:mannequin-slide", this.onSlide)
    this.images.clear()
    cancelAnimationFrame(this.raf)
    this.canvas?.remove()
  }

  onPointerMove(event) {
    if (this.reducedMotion) return
    const rect = this.element.getBoundingClientRect()
    this.pointerActive = true
    this.targetRotation = clamp((event.clientX - rect.left) / Math.max(1, rect.width), 0, 1) - 0.5
    this.targetRotation *= 0.42
  }

  onMannequinChange = (event) => {
    this.setItems(event.detail?.zones || event.detail || {})
  }

  onSlide = (event) => {
    this.setItems(event.detail?.zones || event.detail || {})
  }

  firstItemsFromZones() {
    return Object.fromEntries(
      Object.entries(this.zonesValue || {}).map(([zone, items]) => [zone, Array.isArray(items) ? items[0] : items])
    )
  }

  setItems(items) {
    this.currentItems = items || {}
    Object.values(this.currentItems).forEach(item => {
      if (item?.url) this.load(item.url)
    })
    this.draw()
  }

  setSlide(position) {
    const slides = Array.isArray(this.slidesValue) ? this.slidesValue : []
    const slide = slides[position]
    if (!slide) return
    this.setItems(slide.zones || slide.items || {})
  }

  load(url) {
    if (this.images.has(url)) return this.images.get(url)
    const image = new Image()
    image.decoding = "async"
    image.loading = "lazy"
    const promise = new Promise(resolve => {
      image.onload = () => resolve(image)
      image.onerror = () => resolve(null)
    })
    this.images.set(url, promise)
    image.src = url
    promise.then(() => this.draw())
    return promise
  }

  buildPoints() {
    const points = []
    const sections = ["head", "top", "bottom", "left-arm", "right-arm", "left-leg", "right-leg"]

    for (let i = 0; i < 760; i += 1) {
      points.push({
        section: sections[i % sections.length],
        u: hash(i, 11),
        v: hash(i, 13),
        phase: hash(i, 17) * Math.PI * 2
      })
    }

    return points
  }

  resize() {
    const rect = this.element.getBoundingClientRect()
    this.width = Math.max(180, Math.round(rect.width))
    this.height = Math.max(260, Math.round(rect.height))
    const dpr = Math.min(window.devicePixelRatio || 1, 2)
    this.canvas.width = Math.round(this.width * dpr)
    this.canvas.height = Math.round(this.height * dpr)
    this.canvas.style.width = "100%"
    this.canvas.style.height = "100%"
    this.context?.setTransform(dpr, 0, 0, dpr, 0, 0)
    this.draw()
  }

  frame = () => {
    const now = performance.now()
    if (!this.reducedMotion) {
      if (!this.pointerActive) this.targetRotation = Math.sin(now * 0.00012) * 0.08
      this.rotation += (this.targetRotation - this.rotation) * 0.055
    } else {
      this.rotation = 0
    }
    this.draw(now)
    this.raf = requestAnimationFrame(this.frame)
  }

  draw(now = performance.now()) {
    if (!this.context) return
    const ctx = this.context
    ctx.clearRect(0, 0, this.width, this.height)
    this.drawParticles(ctx, now)
    this.drawGarments(ctx)
    this.drawAxis(ctx)
  }

  drawParticles(ctx, now) {
    const ink = getComputedStyle(this.element).getPropertyValue("--particle-ink").trim() ||
      getComputedStyle(document.documentElement).getPropertyValue("--accent").trim() ||
      "#888"

    ctx.fillStyle = ink
    for (const point of this.points) {
      const geometry = this.pointGeometry(point, now)
      const projected = this.project(geometry.x, geometry.y, geometry.depth)
      const size = 0.7 + geometry.depth * 1.15
      ctx.globalAlpha = 0.07 + geometry.depth * 0.27
      ctx.fillRect(projected.x, projected.y, size, size)
    }
    ctx.globalAlpha = 1
  }

  project(x, y, depth) {
    const scale = Math.min(this.width / 420, this.height / 760)
    const perspective = 1 + depth * 0.16
    return {
      x: this.width * 0.5 + (x - 0.5) * this.width * perspective + Math.sin(this.rotation) * depth * 28 * scale,
      y: y * this.height,
      z: depth
    }
  }

  pointGeometry(point, now) {
    const wobble = this.reducedMotion ? 0 : Math.sin(now * 0.0005 + point.phase) * 0.0012
    let x = 0.5
    let y = 0.5
    let depth = 0.5

    switch (point.section) {
      case "head": {
        const angle = point.u * Math.PI * 2
        const r = 0.075 + point.v * 0.014
        x = 0.5 + Math.cos(angle) * r
        y = 0.105 + Math.sin(angle) * r * 0.72
        depth = 0.55 + Math.cos(angle) * 0.32
        break
      }
      case "top": {
        y = 0.22 + point.v * 0.24
        const width = 0.24 + Math.sin(point.v * Math.PI) * 0.065
        x = 0.5 + (point.u - 0.5) * width
        depth = 0.42 + (1 - Math.abs(point.u - 0.5) * 1.6) * 0.42
        break
      }
      case "bottom": {
        y = 0.49 + point.v * 0.25
        const width = 0.22 - point.v * 0.06
        x = 0.5 + (point.u - 0.5) * width
        depth = 0.34 + (1 - Math.abs(point.u - 0.5) * 1.8) * 0.4
        break
      }
      case "left-arm":
      case "right-arm": {
        const side = point.section === "left-arm" ? -1 : 1
        x = 0.5 + side * (0.27 + point.v * 0.08)
        y = 0.25 + point.v * 0.26
        depth = 0.28 + point.u * 0.45
        break
      }
      case "left-leg":
      case "right-leg": {
        const side = point.section === "left-leg" ? -1 : 1
        x = 0.5 + side * (0.06 + point.u * 0.055)
        y = 0.64 + point.v * 0.28
        depth = 0.24 + point.u * 0.48
        break
      }
    }

    return { x: x + wobble, y, depth: clamp(depth) }
  }

  normalizedItems() {
    return Object.entries(this.currentItems || {})
      .map(([zone, item]) => ({ zone: ZONE_MAP[zone] || zone, item }))
      .filter(({ zone, item }) => BODY[zone] && item?.url)
  }

  drawGarments(ctx) {
    const scale = Math.min(this.width / 420, this.height / 760)
    this.normalizedItems().forEach(({ zone, item }) => {
      this.load(item.url).then(image => {
        if (image) this.drawWrapped(ctx, image, BODY[zone], scale)
      })
    })
  }

  drawWrapped(ctx, image, body, scale) {
    const cols = 12
    const rows = 14
    const x0 = this.width * 0.5
    const y0 = body.top * this.height
    const w = body.width * this.width
    const h = body.height * this.height
    const radius = Math.max(8, body.radius * this.width)
    const sx = image.naturalWidth || image.width || 1
    const sy = image.naturalHeight || image.height || 1

    ctx.save()
    ctx.imageSmoothingEnabled = true

    for (let row = 0; row < rows; row += 1) {
      const v0 = row / rows
      const v1 = (row + 1) / rows

      for (let col = 0; col < cols; col += 1) {
        const u0 = col / cols
        const u1 = (col + 1) / cols
        const a = this.surfacePoint(x0, y0, w, h, radius, u0, v0)
        const b = this.surfacePoint(x0, y0, w, h, radius, u1, v0)
        const c = this.surfacePoint(x0, y0, w, h, radius, u1, v1)
        const d = this.surfacePoint(x0, y0, w, h, radius, u0, v1)

        this.drawTriangle(ctx, image, sx * u0, sy * v0, sx * u1, sy * v0, sx * u1, sy * v1, a, b, c)
        this.drawTriangle(ctx, image, sx * u0, sy * v0, sx * u1, sy * v1, sx * u0, sy * v1, a, c, d)
      }
    }
    ctx.restore()
  }

  surfacePoint(x0, y0, w, h, radius, u, v) {
    const theta = (u - 0.5) * Math.PI * 0.94 + this.rotation * 0.45
    const depth = Math.cos(theta)
    const perspective = 0.74 + Math.max(0, depth) * 0.32
    return {
      x: x0 + Math.sin(theta) * radius * perspective,
      y: y0 + v * h + Math.abs(Math.sin(theta)) * h * 0.018,
      depth: Math.max(0, depth)
    }
  }

  drawTriangle(ctx, image, sx0, sy0, sx1, sy1, sx2, sy2, a, b, c) {
    const ux = sx1 - sx0
    const uy = sy1 - sy0
    const vx = sx2 - sx0
    const vy = sy2 - sy0
    const det = ux * vy - vx * uy
    if (!det) return

    const dx1 = b.x - a.x
    const dy1 = b.y - a.y
    const dx2 = c.x - a.x
    const dy2 = c.y - a.y
    const aa = (dx1 * vy - dx2 * uy) / det
    const bb = (dy1 * vy - dy2 * uy) / det
    const cc = (dx2 * ux - dx1 * vx) / det
    const dd = (dy2 * ux - dy1 * vx) / det
    const e = a.x - aa * sx0 - cc * sy0
    const f = a.y - bb * sx0 - dd * sy0

    const edge = Math.max(0, Math.min(1, a.depth, b.depth, c.depth))
    ctx.save()
    ctx.globalAlpha = 0.86 * Math.pow(edge, 0.48)
    ctx.beginPath()
    ctx.moveTo(a.x, a.y)
    ctx.lineTo(b.x, b.y)
    ctx.lineTo(c.x, c.y)
    ctx.closePath()
    ctx.clip()
    ctx.setTransform(aa, bb, cc, dd, e, f)
    ctx.drawImage(image, sx0, sy0, ux || 1, vy || 1, sx0, sy0, ux || 1, vy || 1)
    ctx.restore()
  }

  drawAxis(ctx) {
    const y = this.height * 0.905
    ctx.globalAlpha = 0.16
    ctx.strokeStyle = getComputedStyle(this.element).getPropertyValue("--particle-ink").trim() || "#888"
    ctx.beginPath()
    ctx.moveTo(this.width * 0.31, y)
    ctx.lineTo(this.width * 0.69, y)
    ctx.stroke()
    ctx.globalAlpha = 1
  }
}
