// Restored from pub2 conceptually, not copied wholesale.
// One job: draw an audio-reactive Radio Bergen tunnel for a local <audio>.

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["canvas", "audio", "label"]
  static values = {
    speed: { type: Number, default: 0.75 },
    reducedSpeed: { type: Number, default: 0.35 }
  }

  connect() {
    this.ctx = this.canvasTarget.getContext("2d", { alpha: false })
    this.frame = this.frame.bind(this)
    this.resize = this.resize.bind(this)
    this.started = false
    this.phase = 0
    this.stars = []
    this.rings = []
    this.pointer = { x: 0, y: 0, active: false }

    this.buildScene()
    this.resize()
    window.addEventListener("resize", this.resize, { passive: true })
    window.addEventListener("pointermove", (event) => this.pointerMove(event), { passive: true })
    this.raf = requestAnimationFrame(this.frame)
  }

  disconnect() {
    cancelAnimationFrame(this.raf)
    window.removeEventListener("resize", this.resize)
    if (this.audioContext && this.audioContext.state !== "closed") {
      this.audioContext.close().catch(() => {})
    }
  }

  start() {
    this.setupAudio()
    this.audioTarget.play().then(() => {
      this.started = true
      this.setLabel("Streaming")
    }).catch((error) => {
      this.setLabel(`Audio blocked: ${error.message}`)
    })
  }

  toggle() {
    if (!this.started || this.audioTarget.paused) {
      this.start()
    } else {
      this.audioTarget.pause()
      this.setLabel("Paused")
    }
  }

  setupAudio() {
    if (this.audioContext) return

    const AudioContextClass = window.AudioContext || window.webkitAudioContext
    if (!AudioContextClass) {
      this.setLabel("Web Audio unavailable")
      return
    }

    this.audioContext = new AudioContextClass()
    this.analyser = this.audioContext.createAnalyser()
    this.analyser.fftSize = 256
    this.frequencyData = new Uint8Array(this.analyser.frequencyBinCount)

    this.compressor = this.audioContext.createDynamicsCompressor()
    this.compressor.threshold.setValueAtTime(-24, this.audioContext.currentTime)
    this.compressor.knee.setValueAtTime(30, this.audioContext.currentTime)
    this.compressor.ratio.setValueAtTime(8, this.audioContext.currentTime)
    this.compressor.attack.setValueAtTime(0.003, this.audioContext.currentTime)
    this.compressor.release.setValueAtTime(0.25, this.audioContext.currentTime)

    this.source = this.audioContext.createMediaElementSource(this.audioTarget)
    this.source.connect(this.analyser)
    this.analyser.connect(this.compressor)
    this.compressor.connect(this.audioContext.destination)
  }

  resize() {
    const dpr = Math.min(2, window.devicePixelRatio || 1)
    const rect = this.canvasTarget.getBoundingClientRect()
    this.width = Math.max(1, Math.floor(rect.width * dpr))
    this.height = Math.max(1, Math.floor(rect.height * dpr))
    this.canvasTarget.width = this.width
    this.canvasTarget.height = this.height
    this.ctx.setTransform(1, 0, 0, 1, 0, 0)
    this.buildScene()
  }

  buildScene() {
    this.stars = Array.from({ length: 96 }, () => ({
      x: (Math.random() - 0.5) * 2,
      y: (Math.random() - 0.5) * 2,
      z: Math.random(),
      b: 0.35 + Math.random() * 0.65
    }))

    this.rings = Array.from({ length: 52 }, (_, index) => ({
      z: index / 52,
      sides: 48,
      twist: Math.random() * Math.PI * 2
    }))
  }

  pointerMove(event) {
    const rect = this.canvasTarget.getBoundingClientRect()
    this.pointer.x = ((event.clientX - rect.left) / rect.width - 0.5) * 2
    this.pointer.y = ((event.clientY - rect.top) / rect.height - 0.5) * 2
    this.pointer.active = true
  }

  frame(now) {
    const energy = this.audioEnergy()
    const reduced = window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches
    const speed = (reduced ? this.reducedSpeedValue : this.speedValue) * (0.4 + energy.average)

    this.phase += 0.014 * speed
    this.draw(energy, speed)
    this.raf = requestAnimationFrame(this.frame)
  }

  audioEnergy() {
    if (!this.analyser || !this.frequencyData) {
      const fallback = 0.5 + Math.sin(this.phase * 3) * 0.2
      return { bass: fallback, mid: fallback * 0.8, high: fallback * 0.6, average: fallback, beat: 0.1 }
    }

    this.analyser.getByteFrequencyData(this.frequencyData)
    const n = this.frequencyData.length
    const bassEnd = Math.floor(n * 0.2)
    const midEnd = Math.floor(n * 0.6)
    let bass = 0
    let mid = 0
    let high = 0

    for (let i = 0; i < bassEnd; i += 1) bass += this.frequencyData[i]
    for (let i = bassEnd; i < midEnd; i += 1) mid += this.frequencyData[i]
    for (let i = midEnd; i < n; i += 1) high += this.frequencyData[i]

    bass /= Math.max(1, bassEnd * 255)
    mid /= Math.max(1, (midEnd - bassEnd) * 255)
    high /= Math.max(1, (n - midEnd) * 255)
    const average = (bass + mid + high) / 3
    const beat = Math.max(0, bass - 0.45)

    return { bass, mid, high, average, beat }
  }

  draw(energy, speed) {
    const ctx = this.ctx
    const cx = this.width / 2
    const cy = this.height / 2
    const min = Math.min(this.width, this.height)

    ctx.fillStyle = "rgb(0,0,0)"
    ctx.fillRect(0, 0, this.width, this.height)

    this.drawStars(ctx, cx, cy, min, energy, speed)
    this.drawTunnel(ctx, cx, cy, min, energy, speed)
  }

  drawStars(ctx, cx, cy, min, energy, speed) {
    ctx.save()
    for (const star of this.stars) {
      star.z -= 0.004 * speed
      if (star.z <= 0) {
        star.z = 1
        star.x = (Math.random() - 0.5) * 2
        star.y = (Math.random() - 0.5) * 2
      }

      const scale = 1 / Math.max(0.04, star.z)
      const x = cx + star.x * min * 0.35 * scale + this.pointer.x * 12
      const y = cy + star.y * min * 0.35 * scale + this.pointer.y * 12
      const light = Math.floor((70 + energy.high * 160) * star.b)

      ctx.fillStyle = `rgb(${Math.floor(light * 0.45)},${Math.floor(light * 0.65)},${light})`
      ctx.fillRect(x, y, 1.5, 1.5)
    }
    ctx.restore()
  }

  drawTunnel(ctx, cx, cy, min, energy, speed) {
    const radiusBase = min * (0.12 + energy.bass * 0.08)
    const pointerX = this.pointer.active ? this.pointer.x * min * 0.08 : 0
    const pointerY = this.pointer.active ? this.pointer.y * min * 0.08 : 0

    ctx.save()
    ctx.lineWidth = Math.max(1, min * 0.0018)

    for (const ring of this.rings) {
      ring.z -= 0.006 * speed
      if (ring.z <= 0) ring.z = 1

      const depth = 1 - ring.z
      const radius = radiusBase * (0.35 + depth * 4.2)
      const alpha = Math.max(0, Math.min(1, depth))
      const x = cx + pointerX * ring.z
      const y = cy + pointerY * ring.z
      const hue = Math.floor(180 + energy.mid * 70 + depth * 45)
      const light = Math.floor(35 + energy.average * 45 + energy.beat * 80)

      ctx.strokeStyle = `hsla(${hue},70%,${light}%,${alpha})`
      ctx.beginPath()

      for (let i = 0; i <= ring.sides; i += 1) {
        const angle = (i / ring.sides) * Math.PI * 2 + this.phase + ring.twist
        const wobble = 1 + Math.sin(angle * 3 + this.phase * 4) * energy.bass * 0.08
        const px = x + Math.cos(angle) * radius * wobble
        const py = y + Math.sin(angle) * radius * wobble
        if (i === 0) ctx.moveTo(px, py)
        else ctx.lineTo(px, py)
      }

      ctx.stroke()
    }

    ctx.restore()
  }

  setLabel(text) {
    if (this.hasLabelTarget) this.labelTarget.textContent = text
  }
}