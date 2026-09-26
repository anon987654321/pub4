const TAU = Math.PI * 2
const GOLDEN_ANGLE = 2.399963229728653

const SURFACE_DEFAULTS = {
  master: { topology: "orb", count: 640 },
  social: { topology: "terrain", count: 420 },
  dating: { topology: "pair", count: 360 },
  luxury: { topology: "ambient", count: 320 },
  radio: { topology: "tunnel", count: 420 },
  mannequin: { topology: "mannequin", count: 520 },
  ambient: { topology: "orb", count: 320 }
}

function hash(index, salt = 0) {
  const value = Math.sin(index * 12.9898 + salt * 78.233) * 43758.5453
  return value - Math.floor(value)
}

function clamp(value, min = 0, max = 1) {
  const number = Number(value)
  if (!Number.isFinite(number)) return min
  return Math.max(min, Math.min(max, number))
}

function signedHash(index, salt = 0) {
  return hash(index, salt) * 2 - 1
}

function valueOr(value, fallback) {
  return value == null ? fallback : value
}

export function normalizeVisual(detail = {}) {
  return {
    topology: detail.topology || detail.canonical_topology || null,
    activity: clamp(valueOr(detail.activity, valueOr(detail.arousal, 0.16))),
    entropy: clamp(valueOr(detail.entropy, 0.2)),
    confidence: clamp(valueOr(detail.confidence, 0.82)),
    arousal: clamp(valueOr(detail.arousal, 0.16)),
    valence: clamp(valueOr(detail.valence, 0)),
    focus: clamp(valueOr(detail.focus, valueOr(detail.confidence, 0.82))),
    bass: clamp(valueOr(detail.bass, 0)),
    mid: clamp(valueOr(detail.mid, 0)),
    high: clamp(valueOr(detail.high, 0)),
    beat: clamp(valueOr(detail.beat, 0)),
    mode: detail.mode || "idle",
    name: detail.name || detail.event || "visual"
  }
}

export function publishVisual(name, detail = {}) {
  const visual = normalizeVisual({ ...detail, name })
  window.dispatchEvent(new CustomEvent("pub4:visual", { detail: visual }))
  return visual
}

function surfaceDefaults(surface) {
  return SURFACE_DEFAULTS[surface] || SURFACE_DEFAULTS.ambient
}

export class VisualField {
  constructor({ canvas, surface = "ambient", topology = null, count = null, local = false } = {}) {
    this.canvas = canvas
    this.surface = surface
    this.topology = topology || surfaceDefaults(surface).topology
    this.count = count || surfaceDefaults(surface).count
    this.local = local
    this.dpr = 1
    this.width = 1
    this.height = 1
    this.time = performance.now()
    this.last = this.time
    this.pointerX = 0.5
    this.pointerY = 0.46
    this.pointerActive = 0
    this.activity = 0.12
    this.entropy = 0.2
    this.confidence = 0.82
    this.arousal = 0.16
    this.valence = 0
    this.focus = 0.82
    this.bass = 0
    this.mid = 0
    this.high = 0
    this.beat = 0
    this.mode = "idle"
    this.points = new Float32Array(0)
    this.reducedMotion = typeof matchMedia == "function" &&
      matchMedia("(prefers-reduced-motion: reduce)").matches

    this.canvas.setAttribute("aria-hidden", "true")
    this.canvas.style.pointerEvents = "none"
    this.canvas.style.imageRendering = "pixelated"

    this.resize()
  }

  resize(width, height) {
    this.width = Math.max(1, Math.round(width || this.canvas.clientWidth || window.innerWidth || 1))
    this.height = Math.max(1, Math.round(height || this.canvas.clientHeight || window.innerHeight || 1))
    this.dpr = this.local ? Math.min(window.devicePixelRatio || 1, 1.5) : 1
    this.canvas.width = Math.max(1, Math.round(this.width * this.dpr))
    this.canvas.height = Math.max(1, Math.round(this.height * this.dpr))
    this.context = this.canvas.getContext("2d", { alpha: true })
    if (!this.context) return
    this.context.setTransform(this.dpr, 0, 0, this.dpr, 0, 0)
    this.seed()
    this.draw(this.time)
  }

  seed() {
    const capacity = Math.max(32, this.count)
    this.points = new Float32Array(capacity * 6)
    for (let i = 0; i < capacity; i += 1) {
      const offset = i * 6
      const target = this.target(i, this.time)
      const spread = this.local ? 8 + hash(i, 41) * 16 : 18 + hash(i, 41) * 52
      const angle = hash(i, 43) * TAU
      this.points[offset] = target.x + Math.cos(angle) * spread
      this.points[offset + 1] = target.y + Math.sin(angle) * spread
      this.points[offset + 2] = 0
      this.points[offset + 3] = 0
      this.points[offset + 4] = hash(i, 47)
      this.points[offset + 5] = 0.2 + hash(i, 53) * 0.8
    }
  }

  signal(detail = {}) {
    const next = normalizeVisual(detail)
    if (next.topology) this.topology = next.topology
    this.activity += (next.activity - this.activity) * 0.38
    this.entropy += (next.entropy - this.entropy) * 0.28
    this.confidence += (next.confidence - this.confidence) * 0.34
    this.arousal += (next.arousal - this.arousal) * 0.32
    this.valence += (next.valence - this.valence) * 0.3
    this.focus += (next.focus - this.focus) * 0.35
    this.bass += (next.bass - this.bass) * 0.48
    this.mid += (next.mid - this.mid) * 0.42
    this.high += (next.high - this.high) * 0.42
    this.beat = Math.max(next.beat, this.beat * 0.72)
    this.mode = next.mode
    this.ensureCount()
  }

  pointer(x, y, active = true) {
    this.pointerX = clamp(x)
    this.pointerY = clamp(y)
    this.pointerActive = active ? 1 : this.pointerActive
    this.activity = Math.min(1, this.activity + 0.035)
  }

  ensureCount() {
    const area = this.width * this.height
    const mobile = area < 420000
    const battery = document.documentElement.dataset.runtimeProfile == "battery"
    const reduced = this.reducedMotion
    const base = surfaceDefaults(this.surface).count
    const next = reduced ? Math.min(104, base) : mobile ? Math.min(260, base) : battery ? Math.min(220, base) : base
    if (next != this.points.length / 6) {
      this.count = next
      this.seed()
    }
  }

  target(index, now) {
    switch (this.topology) {
      case "terrain": return this.terrainTarget(index, now)
      case "pair": return this.pairTarget(index, now)
      case "tunnel": return this.tunnelTarget(index, now)
      case "mannequin": return this.mannequinTarget(index, now)
      case "halo": return this.haloTarget(index, now)
      default: return this.orbTarget(index, now)
    }
  }

  orbTarget(index, now) {
    const angle = index * GOLDEN_ANGLE + hash(index, 3) * 0.22
    const depth = 0.26 + hash(index, 5) * 0.74
    const radius = 0.5 + hash(index, 7) * 0.46
    const breathe = 1 + Math.sin(now * 0.00018 + index * 0.037) * 0.045
    const rx = this.width * (0.28 + this.focus * 0.1)
    const ry = this.height * (0.22 + this.focus * 0.07)
    const cx = this.width * (0.5 + (this.pointerX - 0.5) * 0.025 * this.pointerActive)
    const cy = this.height * (0.46 + (this.pointerY - 0.46) * 0.02 * this.pointerActive)
    return {
      x: cx + Math.cos(angle + now * 0.00002) * rx * radius * breathe,
      y: cy + Math.sin(angle + now * 0.00002) * ry * radius * breathe +
        Math.sin(angle * 3 + now * 0.00026) * this.height * 0.012,
      depth
    }
  }

  terrainTarget(index, now) {
    const across = (index + 0.5) / this.count
    const x = this.width * (across * 1.08 - 0.04)
    const base = this.height * (0.52 + signedHash(index, 19) * 0.16)
    const wave = Math.sin(across * 15.7 + now * 0.00042) * this.height * (0.018 + this.entropy * 0.035)
    const tide = Math.sin(across * 5.2 - now * 0.00013) * this.height * 0.035
    return { x, y: base + wave + tide, depth: 0.35 + hash(index, 23) * 0.65 }
  }

  pairTarget(index, now) {
    const side = index % 2 == 0 ? -1 : 1
    const local = Math.floor(index / 2)
    const ring = 0.12 + hash(local, 29) * 0.74
    const angle = local * GOLDEN_ANGLE + hash(local, 31) * 0.18
    const cx = this.width * (0.5 + side * 0.20)
    const cy = this.height * 0.47
    const pulse = 1 + Math.sin(now * 0.00032 + local * 0.04) * (0.025 + this.arousal * 0.045)
    return {
      x: cx + Math.cos(angle + now * 0.000018 * side) * this.width * 0.16 * ring * pulse,
      y: cy + Math.sin(angle) * this.height * 0.21 * ring,
      depth: 0.35 + hash(index, 37) * 0.65
    }
  }

  tunnelTarget(index, now) {
    const rings = Math.max(1, Math.floor(this.count / 24))
    const ring = index % rings
    const arm = Math.floor(index / rings)
    const t = (ring + 0.5) / rings
    const angle = arm * GOLDEN_ANGLE + t * TAU
    const depth = 1 - t
    const radius = Math.hypot(this.width, this.height) * (0.04 + depth * 0.44)
    const travel = now * 0.00018
    const perspective = 0.5 + depth * 1.4
    return {
      x: this.width * 0.5 + Math.cos(angle + travel) * radius * perspective,
      y: this.height * 0.5 + Math.sin(angle + travel) * radius * perspective,
      depth: 0.25 + depth * 0.75
    }
  }

  haloTarget(index, now) {
    const angle = index * GOLDEN_ANGLE
    const wobble = Math.sin(now * 0.0003 + index * 0.08) * 0.025
    const radius = this.width * (0.16 + (0.18 + this.arousal * 0.1) * (0.3 + hash(index, 59)))
    return {
      x: this.width * 0.5 + Math.cos(angle) * radius,
      y: this.height * 0.46 + Math.sin(angle) * radius * 0.68 + wobble * this.height,
      depth: 0.3 + hash(index, 61) * 0.7
    }
  }

  mannequinTarget(index, now) {
    const section = index % 8
    const u = ((Math.floor(index / 8) + 0.5) / Math.ceil(this.count / 8))
    const jitter = signedHash(index, 71)
    const w = this.width
    const h = this.height
    const center = w * 0.5

    if (section == 0) {
      const angle = u * TAU
      return {
        x: center + Math.cos(angle) * w * 0.17 * (0.92 + 0.08 * Math.sin(now * 0.0002)),
        y: h * 0.15 + Math.sin(angle) * h * 0.075,
        depth: 0.75 + hash(index, 73) * 0.25
      }
    }

    if (section <= 2) {
      const y = h * (0.24 + u * 0.31)
      const shoulder = w * (0.12 + 0.12 * Math.sin(Math.PI * u))
      return {
        x: center + (section == 1 ? -shoulder : shoulder) + jitter * 1.8,
        y: y + Math.sin(u * Math.PI + now * 0.0002) * 1.5,
        depth: 0.42 + hash(index, 79) * 0.58
      }
    }

    if (section <= 5) {
      const y = h * (0.49 + u * 0.43)
      const side = section % 2 == 0 ? -1 : 1
      const leg = w * 0.09 + u * w * 0.03
      return {
        x: center + side * leg + jitter * 2,
        y,
        depth: 0.35 + hash(index, 83) * 0.65
      }
    }

    const y = h * (0.36 + u * 0.30)
    const side = section == 6 ? -1 : 1
    return {
      x: center + side * (w * 0.30 + u * w * 0.07),
      y: y + jitter * 1.6,
      depth: 0.3 + hash(index, 89) * 0.7
    }
  }

  step(now) {
    const dt = Math.min(0.035, Math.max(0.001, (now - this.last) / 1000))
    this.last = now

    const motion = this.reducedMotion ? 0 : 1
    this.activity += (0.12 - this.activity) * dt * 0.55
    this.entropy += (0.2 - this.entropy) * dt * 0.35
    this.confidence += (0.82 - this.confidence) * dt * 0.32
    this.arousal += (0.16 - this.arousal) * dt * 0.3
    this.valence += (0 - this.valence) * dt * 0.24
    this.pointerActive += (0 - this.pointerActive) * dt * 2.4

    const spring = this.local ? 5.8 : 4.3 + this.activity * 1.4
    const damping = Math.exp(-(this.local ? 7.2 : 6.3) * dt)
    const repel = this.local ? 18 : 9

    for (let i = 0; i < this.points.length; i += 6) {
      const index = i / 6
      const target = this.target(index, now)
      let x = this.points[i]
      let y = this.points[i + 1]
      let vx = this.points[i + 2]
      let vy = this.points[i + 3]
      const phase = this.points[i + 4]
      const depth = this.points[i + 5]

      vx += (target.x - x) * spring * dt
      vy += (target.y - y) * spring * dt

      const wobble = Math.sin(now * 0.00043 + phase * TAU) *
        (this.local ? 0.9 + this.activity * 2.5 : 3 + this.entropy * 9)
      vx += wobble * 0.16 * motion
      vy -= wobble * 0.12 * motion

      if (this.pointerActive > 0.01 && !this.reducedMotion) {
        const px = this.pointerX * this.width
        const py = this.pointerY * this.height
        const dx = x - px
        const dy = y - py
        const distance = Math.max(12, Math.hypot(dx, dy))
        if (distance < Math.min(220, Math.max(80, Math.min(this.width, this.height) * 0.24))) {
          const radius = Math.min(220, Math.max(80, Math.min(this.width, this.height) * 0.24))
          const proximity = 1 - distance / radius
          const force = (22 + this.activity * 46) * proximity * proximity * depth
          vx += (dx / distance) * force * dt
          vy += (dy / distance) * force * dt
        }
      }

      vx *= damping
      vy *= damping
      x += vx * dt * 64
      y += vy * dt * 64

      this.points[i] = x
      this.points[i + 1] = y
      this.points[i + 2] = vx
      this.points[i + 3] = vy
      this.points[i + 5] = depth

      if (repel && index % 17 == 0) {
        const neighbor = ((index + repel) % this.count) * 6
        const dx = this.points[i] - this.points[neighbor]
        const dy = this.points[i + 1] - this.points[neighbor + 1]
        const distance = Math.max(8, Math.hypot(dx, dy))
        if (distance < 20) {
          this.points[i] += dx / distance
          this.points[i + 1] += dy / distance
        }
      }
    }
  }

  color() {
    const root = document.documentElement
    const style = getComputedStyle(this.local ? this.canvas.parentElement || root : root)
    return style.getPropertyValue("--particle-ink").trim() ||
      style.getPropertyValue("--master-accent").trim() ||
      style.getPropertyValue("--accent").trim() ||
      "#7b8cde"
  }

  draw(now) {
    if (!this.context) return
    this.context.clearRect(0, 0, this.width, this.height)

    const ink = this.color()
    const energy = this.bass * 0.45 + this.mid * 0.32 + this.high * 0.18 + this.beat * 0.42
    const baseAlpha = this.local ? 0.18 : 0.055
    const boost = Math.min(0.22, this.arousal * 0.08 + energy * 0.12)

    for (let i = 0; i < this.points.length; i += 6) {
      const depth = this.points[i + 5]
      const pointAlpha = Math.min(
        this.local ? 0.88 : 0.24,
        baseAlpha + depth * (this.local ? 0.42 : 0.11) + boost
      )
      this.context.globalAlpha = pointAlpha
      this.context.fillStyle = ink
      this.context.fillRect(Math.round(this.points[i]), Math.round(this.points[i + 1]), 1, 1)
    }

    if (this.topology == "pair" && !this.reducedMotion) {
      this.context.globalAlpha = Math.min(0.12, 0.02 + this.confidence * 0.06)
      this.context.beginPath()
      this.context.moveTo(this.width * 0.3, this.height * 0.47)
      this.context.lineTo(this.width * 0.7, this.height * 0.47)
      this.context.strokeStyle = ink
      this.context.lineWidth = 1
      this.context.stroke()
    }

    this.context.globalAlpha = 1
  }

  frame(now = performance.now()) {
    this.step(now)
    this.draw(now)
    return {
      topology: this.topology,
      activity: this.activity,
      entropy: this.entropy,
      confidence: this.confidence,
      arousal: this.arousal,
      valence: this.valence,
      focus: this.focus,
      bass: this.bass,
      mid: this.mid,
      high: this.high,
      beat: this.beat,
      mode: this.mode
    }
  }

  destroy() {
    this.context = null
    this.points = new Float32Array(0)
  }
}