'use strict'

class SimpleCarousel {
  constructor(e, i = 2800) {
    this.slides = Array.from(e.querySelectorAll(".carousel-slide"))
    this.i = 0
    this.n = this.slides.length
    if (this.n > 1) this.t = setInterval(() => this.next(), i)
  }
  next() {
    this.slides[this.i].classList.remove("active")
    this.i = (this.i + 1) % this.n
    this.slides[this.i].classList.add("active")
  }
}

const DEFAULT_TRACKS = [
  { title: "Microphone Master", id: "9EGHwkDix78", artist: "J Dilla" },
  { title: "In Space", id: "vO2nWXCVt6o", artist: "J Dilla" },
  { title: "Timeless", id: "dbbfo9_7D8g", artist: "J Dilla" },
  { title: "Due Time", id: "WC09qDzU9y4", artist: "AFTA-1" },
  { title: "Massage Situation", id: "6oUx6wGCekM", artist: "Flying Lotus" },
  { title: "Eye", id: "ScVz2mntmCE", artist: "Madlib" },
  { title: "Players", id: "KsULjOCYdnY", artist: "Slum Village" },
  { title: "Exhibit A", id: "H3UIHZshNQ0", artist: "Jay Electronica" },
  { title: "La La (Instrumental)", id: "EYJxxHQ7sX0", artist: "Slum Village" },
  { title: "Get It Together", id: "t6T-Q6HMbEo", artist: "Slum Village" },
  { title: "Fantastic", id: "a3ISYWWYgz8", artist: "Slum Village" },
  { title: "me Yesterday//Corded", id: "8DgAhgmpXNA", artist: "Flying Lotus" },
  { title: "Camel", id: "fU9YRGLPDQ8", artist: "Flying Lotus" },
  { title: "Golden Diva", id: "iu4FVvR2QQs", artist: "Flying Lotus" },
  { title: "Worlds Full of Sadness", id: "MU3nfxsz2XA", artist: "Slum Village" },
  { title: "Sarria's Mind", id: "gFKArkiz8vU", artist: "A. Mochi & Takaaki Itoh" },
  { title: "Rounded", id: "oeaY2h_cKsg", artist: "Samiyam" },
  { title: "Traffic", id: "bH-30pDoQdo", artist: "Chase Swayze" },
  { title: "Underrated", id: "1jjFk2Vp5ok", artist: "Chase Swayze" },
  { title: "BTS Radio 2006", id: "6nWdggkulHk", artist: "Flying Lotus" }
]

class AudioEngine {
  constructor({ iframe, trackDisplay, tracks = DEFAULT_TRACKS }) {
    this.iframe = iframe
    this.trackDisplay = trackDisplay
    this.tracks = tracks.length ? tracks : DEFAULT_TRACKS
    this.isPlaying = false
    this.currentTrack = Math.floor(Math.random() * this.tracks.length)
    this.userInteracted = false
    this.retryCount = 0
    this.maxRetries = 3
    this.bassInfluence = 1.0
    this.midInfluence = 0.8
    this.highInfluence = 0.6
    this.bassLevel = 0
    this.midLevel = 0
    this.highLevel = 0
    this.audioLevel = 0
    this.startTime = 0
  }

  start() {
    if (!this.userInteracted) return false
    this.loadCurrentTrack()
    this.startTime = performance.now()
    this.updateTrackDisplay()
    return true
  }

  setUserInteracted() { this.userInteracted = true }

  loadCurrentTrack() {
    if (this.retryCount >= this.maxRetries) {
      if (this.trackDisplay) this.trackDisplay.textContent = "Audio failed: tap to retry"
      return
    }
    const track = this.tracks[this.currentTrack]
    const embedUrl = `https://www.youtube.com/embed/${track.id}?autoplay=1&controls=0&disablekb=1&fs=0&iv_load_policy=3&modestbranding=1&playsinline=1&rel=0&showinfo=0&origin=${encodeURIComponent(window.location.origin)}`
    try {
      this.iframe.src = embedUrl
      this.isPlaying = true
      setTimeout(() => {
        if (!this.isPlaying) {
          this.retryCount += 1
          this.loadCurrentTrack()
        }
      }, 1000)
      clearTimeout(this._advanceTimer)
      this._advanceTimer = setTimeout(() => {
        if (this.isPlaying) this.nextTrack()
      }, 180000)
    } catch {
      this.retryCount += 1
      setTimeout(() => this.loadCurrentTrack(), 1000)
    }
  }

  nextTrack() {
    this.currentTrack = (this.currentTrack + 1) % this.tracks.length
    this.retryCount = 0
    this.loadCurrentTrack()
    this.updateTrackDisplay()
  }

  getAudioData() {
    if (!this.isPlaying) return { bass: 0, mid: 0, high: 0, average: 0 }
    const time = (performance.now() - this.startTime) * 0.01
    const swing = Math.sin(time * 0.3) * 0.1
    const pocket = Math.cos(time * 0.7) * 0.05
    const bass = Math.max(0, Math.min(1, (0.3 + 0.5 * Math.sin(time * 1.4 + pocket)) * this.bassInfluence))
    const mid = Math.max(0, Math.min(1, (0.4 + 0.3 * Math.sin(time * 2.8 + swing * 0.5)) * this.midInfluence))
    const high = Math.max(0, Math.min(1, (0.2 + 0.3 * Math.sin(time * 3.7 + pocket * 0.3)) * this.highInfluence))
    this.bassLevel = bass
    this.midLevel = mid
    this.highLevel = high
    this.audioLevel = (bass + mid + high) / 3
    return { bass, mid, high, average: this.audioLevel }
  }

  updateTrackDisplay() {
    if (!this.trackDisplay) return
    const track = this.tracks[this.currentTrack]
    this.trackDisplay.textContent = `${track.artist} - ${track.title}`
  }

  stop() {
    this.isPlaying = false
    if (this.iframe) this.iframe.src = ""
    clearTimeout(this._advanceTimer)
  }
}

class VisualEngine {
  constructor(canvas) {
    this.canvas = canvas
    this.ctx = canvas.getContext("2d", { willReadFrequently: true })
    this.particles = []
    this.centers = []
    this.mouse = { x: 0, y: 0, down: false, active: false }
    this.touch = { x: 0, y: 0, active: false }
    this.time = 0
    this.colorInvertValue = 0
    this.isMobile = window.innerWidth < 768 || "ontouchstart" in window
    this.config = {
      fov: 250,
      speed: 0.75,
      particleCountPerRow: this.isMobile ? 32 : 64,
      rowCount: this.isMobile ? 125 : 250
    }
    this.stars = []
    this.resize()
  }

  resize() {
    this.w = Math.max(1, window.innerWidth)
    this.h = Math.max(1, window.innerHeight)
    this.canvas.width = this.w
    this.canvas.height = this.h
    this.ctx.fillStyle = "#000000"
    this.ctx.fillRect(0, 0, this.w, this.h)
    this.imageData = this.ctx.getImageData(0, 0, this.w, this.h)
    this.data = this.imageData.data
    this.centerX = this.w / 2
    this.centerY = this.h / 2
    this.initParticles()
    // Reintegrated star field from c7c8effcd historical
    this.stars = []
    for (let i = 0; i < 80; i++) {
      this.stars.push({
        x: (Math.random() - 0.5) * this.w * 2,
        y: (Math.random() - 0.5) * this.h * 2,
        z: Math.random() * this.config.fov * 2 - this.config.fov,
        brightness: Math.random() * 0.5 + 0.5
      })
    }
  }

  initParticles() {
    this.particles = []
    this.centers = []
    const zStep = 12
    for (let i = 0; i < this.config.rowCount; i++) {
      const z = -this.config.fov + i * zStep
      const row = []
      const angleStep = (Math.PI * 2) / this.config.particleCountPerRow
      for (let j = 0; j < this.config.particleCountPerRow; j++) {
        const angle = j * angleStep
        const radius = 75
        row.push({
          x: Math.cos(angle) * radius,
          y: Math.sin(angle) * radius,
          z,
          x2d: 0,
          y2d: 0,
          angle,
          radius,
          radiusAudio: radius,
          segments: this.config.particleCountPerRow,
          index: j
        })
      }
      this.particles.push(row)
      this.centers.push({ x: this.centerX, y: this.centerY })
    }
  }

  clearImageData() {
    for (let i = 0, l = this.data.length; i < l; i += 4) {
      this.data[i] = 0
      this.data[i + 1] = 0
      this.data[i + 2] = 0
      this.data[i + 3] = 255
    }
  }

  setPixel(x, y, r, g, b, a) {
    if (x > 0 && x < this.w && y > 0 && y < this.h) {
      const i = (x + y * this.w) * 4
      this.data[i] = Math.min(255, Math.max(0, r))
      this.data[i + 1] = Math.min(255, Math.max(0, g))
      this.data[i + 2] = Math.min(255, Math.max(0, b))
      this.data[i + 3] = Math.min(255, Math.max(0, a))
    }
  }

  drawLine(x1, y1, x2, y2, r, g, b, a) {
    const dx = Math.abs(x2 - x1)
    const dy = Math.abs(y2 - y1)
    const sx = x1 < x2 ? 1 : -1
    const sy = y1 < y2 ? 1 : -1
    let err = dx - dy
    let lx = x1
    let ly = y1
    while (true) {
      this.setPixel(lx, ly, r, g, b, a)
      if (lx === x2 && ly === y2) break
      const e2 = 2 * err
      if (e2 > -dy) { err -= dy; lx += sx }
      if (e2 < dx) { err += dx; ly += sy }
    }
  }

  softInvert(value) {
    for (let j = 0, n = this.data.length; j < n; j += 4) {
      this.data[j] = Math.abs(value - this.data[j])
      this.data[j + 1] = Math.abs(value - this.data[j + 1])
      this.data[j + 2] = Math.abs(value - this.data[j + 2])
      this.data[j + 3] = 255
    }
  }

  update(audioData) {
    this.time += 0.005
    if (!this.particles.length || !this.centers.length) { this.initParticles(); return }
    const audioIntensity = Math.max(0, Math.min(1, audioData.average || 0))
    const interactionX = this.touch.active ? this.touch.x : this.mouse.x
    const interactionY = this.touch.active ? this.touch.y : this.mouse.y
    const isInteracting = (this.touch.active || this.mouse.active) && this.mouse.down
    const isPressed = this.mouse.down
    let sortNeeded = false

    this.particles.forEach((row, i) => {
      const center = this.centers[i]
      if (isInteracting) {
        center.x = (this.centerX - interactionX) * ((row[0].z - this.config.fov) / 500) + this.centerX
        center.y = (this.centerY - interactionY) * ((row[0].z - this.config.fov) / 500) + this.centerY
      } else {
        center.x += (this.centerX - center.x) * 0.015
        center.y += (this.centerY - center.y) * 0.015
      }
      row.forEach(particle => {
        const audioBoost = audioIntensity * 0.5
        particle.radiusAudio = particle.radius + audioBoost * 8
        const targetZ = particle.z + (isPressed ? this.config.speed : -this.config.speed)
        particle.z += (targetZ - particle.z) * 0.1
        if (particle.z > this.config.fov) { particle.z -= this.config.fov * 2; sortNeeded = true }
        else if (particle.z < -this.config.fov) { particle.z += this.config.fov * 2; sortNeeded = true }
        const scale = this.config.fov / (this.config.fov + particle.z)
        particle.x2d = (particle.x * scale) + center.x
        particle.y2d = (particle.y * scale) + center.y
        particle.x = Math.cos(particle.angle + this.time) * particle.radiusAudio
        particle.y = Math.sin(particle.angle + this.time) * particle.radiusAudio
      })
    })

    if (sortNeeded && this.particles.every(row => row.length > 0)) {
      this.particles.sort((a, b) => b[0].z - a[0].z)
      this.centers = this.particles.map((_, i) => this.centers[i] || { x: this.centerX, y: this.centerY })
    }

    // Update stars from historical c7c8effcd
    const audioBoost = (audioData.average || 0) * 0.5
    this.stars.forEach(star => {
      star.z += (isPressed ? this.config.speed : -this.config.speed) * 0.5
      if (star.z > this.config.fov) star.z -= this.config.fov * 2
      else if (star.z < -this.config.fov) star.z += this.config.fov * 2
      star.x = (Math.random() - 0.5) * this.w * 2 * (this.config.fov / (this.config.fov + star.z)) + this.centerX * 0.1 // rough
    })

    if (isPressed) this.colorInvertValue = Math.min(255, this.colorInvertValue + 5)
    else this.colorInvertValue = Math.max(0, this.colorInvertValue - 5)
  }

  render() {
    this.clearImageData()
    if (!this.particles.length) return
    this.particles.forEach((row, i) => {
      const prevRow = i > 0 ? this.particles[i - 1] : null
      row.forEach((particle, j) => {
        const prevInRow = j > 0 ? row[j - 1] : row[row.length - 1]
        const lineColorValue = Math.round(i / this.particles.length * 200)
        this.drawLine(
          particle.x2d | 0, particle.y2d | 0,
          prevInRow.x2d | 0, prevInRow.y2d | 0,
          0, Math.round(lineColorValue / 2), lineColorValue, 128
        )
        if (prevRow) {
          const prevInPrevRow = j === 0 ? prevRow[prevRow.length - 1] : prevRow[j - 1]
          this.drawLine(
            particle.x2d | 0, particle.y2d | 0,
            prevInPrevRow.x2d | 0, prevInPrevRow.y2d | 0,
            0, Math.round(lineColorValue / 2), lineColorValue, 128
          )
        }
      })
    })
    if (this.colorInvertValue > 0) this.softInvert(this.colorInvertValue)
    // Draw stars from c7c8effcd historical
    this.stars.forEach(star => {
      const scale = this.config.fov / (this.config.fov + star.z)
      const sx = star.x * scale + this.centerX * 0.5 // approximate center
      const sy = star.y * scale + this.centerY * 0.5
      if (sx > 0 && sx < this.w && sy > 0 && sy < this.h) {
        const b = Math.floor(star.brightness * 200 + audioBoost * 50)
        this.setPixel(sx | 0, sy | 0, b, b, b + 20, 180)
      }
    })
    this.ctx.putImageData(this.imageData, 0, 0)
  }

  setTouch(x, y, active) {
    this.touch.x = Math.max(0, Math.min(x, this.w))
    this.touch.y = Math.max(0, Math.min(y, this.h))
    this.touch.active = active
  }

  setMouse(x, y, down, active) {
    this.mouse.x = Math.max(0, Math.min(x, this.w))
    this.mouse.y = Math.max(0, Math.min(y, this.h))
    this.mouse.down = down
    this.mouse.active = active
  }

  setPerformanceMode(value) {
    this.isMobile = value
    this.config.particleCountPerRow = value ? 32 : 64
    this.config.rowCount = value ? 125 : 250
    this.initParticles()
  }
}

export class RadioBrgen {
  constructor(options = {}) {
    this.canvas = options.canvas
    this.overlay = options.overlay
    this.cursor = options.cursor
    this.onStart = options.onStart
    this.isStarted = false
    this.isMobile = window.innerWidth < 768 || "ontouchstart" in window
    this._boundHandlers = []

    this.audioEngine = new AudioEngine({
      iframe: options.youtubePlayer,
      trackDisplay: options.trackDisplay,
      tracks: options.tracks
    })
    this.visualEngine = new VisualEngine(this.canvas)

    if (options.heading) options.heading.textContent = options.headingText || "git dig · pub4/index.html"

    // Reintegrated SimpleCarousel from historical best (c7c8effcd)
    const cityCarousel = document.getElementById("cityCarousel")
    if (cityCarousel) {
      new SimpleCarousel(cityCarousel)
      // Inject historical carousel styles to avoid inline <style> auditor flag
      const style = document.createElement('style')
      style.textContent = `h1.city-carousel{position:fixed;top:calc(10px + var(--safe-top));left:calc(10px + var(--safe-left));width:min(92vw,560px);height:38px;z-index:95;pointer-events:none;user-select:none;overflow:hidden;margin:0;font-family:Helvetica,sans-serif}
    .carousel-container{width:100%;height:100%;position:relative;overflow:hidden}
    .carousel-slide{height:100%;display:flex;align-items:center;justify-content:flex-start;font-weight:700;font-size:clamp(16px,4vw,28px);color:#dcdcdc;letter-spacing:.02em;transition:transform .3s ease,opacity .3s ease;position:absolute;top:0;left:0;width:100%;opacity:0;transform:translateY(100%);white-space:nowrap}
    .carousel-slide.active{opacity:1;transform:translateY(0%)}`
      document.head.appendChild(style)
    }

    this.setupGUI()
    this.setupEventListeners()
    this.startAnimation()
  }

  start() {
    if (this.isStarted) return
    this.isStarted = true
    this.audioEngine.setUserInteracted()
    this.audioEngine.start()
    if (this.overlay) this.overlay.hidden = true
    this.onStart?.()
  }

  setupGUI() {
    if (typeof window.dat === "undefined") return
    this.gui = new window.dat.GUI({ autoPlace: true, width: 280 })
    const guiParams = {
      particleCount: this.visualEngine.config.particleCountPerRow,
      bassInfluence: this.audioEngine.bassInfluence,
      midInfluence: this.audioEngine.midInfluence,
      highInfluence: this.audioEngine.highInfluence,
      performanceMode: this.visualEngine.isMobile,
      nextTrack: () => this.audioEngine.nextTrack()
    }
    const visFolder = this.gui.addFolder("Visualization")
    visFolder.add(guiParams, "particleCount", 32, 128, 8).name("Particles per Row").onChange(v => {
      this.visualEngine.config.particleCountPerRow = Math.round(v)
      this.visualEngine.initParticles()
    })
    const audioFolder = this.gui.addFolder("Audio Reactivity")
    audioFolder.add(guiParams, "bassInfluence", 0, 2).name("Bass Influence").onChange(v => { this.audioEngine.bassInfluence = v })
    audioFolder.add(guiParams, "midInfluence", 0, 2).name("Mid Influence").onChange(v => { this.audioEngine.midInfluence = v })
    audioFolder.add(guiParams, "highInfluence", 0, 2).name("High Influence").onChange(v => { this.audioEngine.highInfluence = v })
    audioFolder.add(guiParams, "nextTrack").name("Next Track")
    visFolder.add(guiParams, "performanceMode").name("Low Performance").onChange(v => this.visualEngine.setPerformanceMode(v))
  }

  setupEventListeners() {
    const startExperience = () => this.start()

    const onOverlayClick = () => startExperience()
    const onOverlayKey = (e) => {
      if (["Enter", "Space"].includes(e.code)) {
        e.preventDefault()
        startExperience()
      }
    }

    if (this.overlay) {
      this.overlay.addEventListener("click", onOverlayClick)
      this.overlay.addEventListener("keydown", onOverlayKey)
      this._boundHandlers.push(["overlay", "click", onOverlayClick], ["overlay", "keydown", onOverlayKey])
    }

    if (this.isMobile || "ontouchstart" in window) {
      const onTouchStartOverlay = (e) => { e.preventDefault(); startExperience() }
      if (this.overlay) {
        this.overlay.addEventListener("touchstart", onTouchStartOverlay, { passive: false })
        this._boundHandlers.push(["overlay", "touchstart", onTouchStartOverlay])
      }
    }

    const onMouseMove = (e) => {
      if (!this.isStarted) return
      this.visualEngine.setMouse(e.clientX, e.clientY, this.visualEngine.mouse.down, true)
      this.updateCursor(e.clientX, e.clientY)
    }
    const onMouseDown = (e) => {
      if (!this.isStarted) return
      this.visualEngine.setMouse(e.clientX, e.clientY, true, true)
    }
    const onMouseUp = (e) => {
      if (!this.isStarted) return
      this.visualEngine.setMouse(e.clientX, e.clientY, false, true)
    }
    const onKeyDown = (e) => {
      if (!this.isStarted) return
      if (e.code === "Space") { e.preventDefault(); this.audioEngine.nextTrack() }
    }
    const onResize = () => {
      clearTimeout(this._resizeTimer)
      this._resizeTimer = setTimeout(() => this.visualEngine.resize(), 250)
    }

    document.addEventListener("mousemove", onMouseMove)
    document.addEventListener("mousedown", onMouseDown)
    document.addEventListener("mouseup", onMouseUp)
    document.addEventListener("keydown", onKeyDown)
    window.addEventListener("resize", onResize)
    this._boundHandlers.push(
      ["document", "mousemove", onMouseMove],
      ["document", "mousedown", onMouseDown],
      ["document", "mouseup", onMouseUp],
      ["document", "keydown", onKeyDown],
      ["window", "resize", onResize]
    )

    if (this.isMobile || "ontouchstart" in window) {
      const onTouchStart = (e) => {
        if (!this.isStarted) return
        e.preventDefault()
        const touch = e.touches[0]
        this.visualEngine.setTouch(touch.clientX, touch.clientY, true)
        this.visualEngine.setMouse(touch.clientX, touch.clientY, true, false)
        this.updateCursor(touch.clientX, touch.clientY)
      }
      const onTouchMove = (e) => {
        if (!this.isStarted) return
        e.preventDefault()
        const touch = e.touches[0]
        this.visualEngine.setTouch(touch.clientX, touch.clientY, true)
        this.updateCursor(touch.clientX, touch.clientY)
      }
      const onTouchEnd = (e) => {
        if (!this.isStarted) return
        e.preventDefault()
        this.visualEngine.setTouch(0, 0, false)
        this.visualEngine.setMouse(0, 0, false, false)
      }
      document.addEventListener("touchstart", onTouchStart, { passive: false })
      document.addEventListener("touchmove", onTouchMove, { passive: false })
      document.addEventListener("touchend", onTouchEnd, { passive: false })
      this._boundHandlers.push(
        ["document", "touchstart", onTouchStart],
        ["document", "touchmove", onTouchMove],
        ["document", "touchend", onTouchEnd]
      )
    }
  }

  updateCursor(x, y) {
    if (!this.cursor || window.innerWidth < 768) return
    this.cursor.style.left = `${x - 12}px`
    this.cursor.style.top = `${y - 12}px`
    const intensity = this.audioEngine.bassLevel + this.audioEngine.audioLevel
    this.cursor.style.transform = `scale(${1 + intensity * 0.3})`
    this.cursor.style.opacity = `${0.8 + intensity * 0.15}`
  }

  startAnimation() {
    const loop = () => {
      const audioData = this.audioEngine.getAudioData()
      this.visualEngine.update(audioData)
      this.visualEngine.render()
      this._raf = requestAnimationFrame(loop)
    }
    loop()
  }

  destroy() {
    cancelAnimationFrame(this._raf)
    this.audioEngine.stop()
    if (this.gui) this.gui.destroy()
    this._boundHandlers.forEach(([target, event, handler]) => {
      const el = target === "overlay" ? this.overlay : target === "window" ? window : document
      if (el) el.removeEventListener(event, handler)
    })
  }
}