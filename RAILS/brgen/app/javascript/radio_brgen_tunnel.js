import { publishVisual } from "pub4/visual_field"
import { AudioEngine } from "radio_brgen_audio"
import { initialTrackIndex, OPENING_TRACK_ID } from "radio_brgen_audio"
import { VisualEngine } from "radio_brgen_visual"
// The ring modes live in radio_brgen_modes; radio_brgen_visual imports them
// but does not re-export them, so asking it for MODES failed the whole module.
import { MODES } from "radio_brgen_modes"
export { initialTrackIndex } from "radio_brgen_audio"

'use strict'

export class RadioBrgen {
  constructor(options = {}) {
    this.canvas = options.canvas
    this.overlay = options.overlay
    this.onStart = options.onStart
    this.isStarted = false
    this.isMobile = window.innerWidth < 768 || "ontouchstart" in window
    this._boundHandlers = []
    // The tunnel owns the queue and its start: the legacy opener when it is in
    // the list, otherwise the first ordered item — never a random pick, so a
    // single-track queue and a curated set both open the same way every load.
    this.tracks = options.tracks ?? []
    this.currentTrack = initialTrackIndex(this.tracks, OPENING_TRACK_ID)
    this.audioEngine = new AudioEngine({
      iframe: options.youtubePlayer,
      trackDisplay: options.trackDisplay,
      sourceCredit: options.sourceCredit,
      tracks: this.tracks
    })
    this.visualEngine = new VisualEngine(this.canvas)

    if (options.heading && options.headingText) {
      options.heading.textContent = options.headingText
    }

    this.setupEventListeners()
    this.startAnimation()
  }

  start() {
    if (this.isStarted) return
    this.isStarted = true
    this.audioEngine.setUserInteracted()
    this.audioEngine.start()
    this._bindTilt?.()
    this.audioEngine.publishTrack?.()
    if (this.overlay) this.overlay.hidden = true
    this.onStart?.()
  }

  setupEventListeners() {
    const startExperience = () => this.start()

    const bindTilt = async () => {
      if (window.matchMedia?.("(prefers-reduced-motion: reduce)")?.matches) return
      const Ctor = window.DeviceOrientationEvent
      if (!Ctor) return
      if (typeof Ctor.requestPermission === "function") {
        try {
          const permission = await Ctor.requestPermission()
          if (permission !== "granted") return
        } catch {
          return
        }
      }
      this._tiltHandler = (event) => {
        if (event.gamma == null) return
        const gamma = Math.max(-20, Math.min(20, event.gamma || 0))
        const beta = Math.max(-20, Math.min(20, (event.beta || 0) - 45))
        this.visualEngine.tilt.x = gamma / 20 * 0.08
        this.visualEngine.tilt.y = beta / 20 * 0.08
      }
      window.addEventListener("deviceorientation", this._tiltHandler, { passive: true })
    }

    const onOverlayClick = () => startExperience()
    const onOverlayKey = (e) => {
      if (["Enter", "Space"].includes(e.code)) {
        e.preventDefault()
        startExperience()
      }
    }

    this._bindTilt = bindTilt
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
      // The pen's ← and →: step through the ring modes and say which one.
      if (e.code === "ArrowRight" || e.code === "ArrowLeft") {
        e.preventDefault()
        const mode = this.visualEngine.shiftMode(e.code === "ArrowRight" ? 1 : -1)
        this.audioEngine.updateTrackDisplay(`Mode ${mode + 1}/${MODES.length}: ${MODES[mode].name}`)
      }
    }
    const onResize = () => {
      clearTimeout(this._resizeTimer)
      this._resizeTimer = setTimeout(() => {
        this.visualEngine.resize()

      }, 250)
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
      }
      const onTouchMove = (e) => {
        if (!this.isStarted) return
        e.preventDefault()
        const touch = e.touches[0]
        this.visualEngine.setTouch(touch.clientX, touch.clientY, true)
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

  startAnimation() {
    // A single throw inside update()/render() previously killed the entire
    // animation forever -- requestAnimationFrame is never rescheduled once
    // an exception unwinds past this closure, and canvas particle math is
    // exactly the kind of code that hits a rare NaN/divide-by-zero after a
    // few seconds of continuous audio-driven motion. Skip the bad frame,
    // keep the loop alive, so a transient glitch reads as a stutter, not
    // a dead animation.
    const loop = () => {
      try {
        const audioData = this.audioEngine.getAudioData()
        this.visualEngine.update(audioData)
        const visualNow = performance.now()
        if (!this._lastVisualSignalAt || visualNow - this._lastVisualSignalAt >= 50) {
          this._lastVisualSignalAt = visualNow
          publishVisual("radio:audio", {
            topology: "tunnel",
            mode: "radio:tunnel",
            activity: audioData.average,
            arousal: audioData.average,
            confidence: 0.92,
            bass: audioData.bass,
            mid: audioData.mid,
            high: audioData.high,
            beat: audioData.beat
          })
        }
        this.visualEngine.render()
      } catch (error) {
        if (typeof console !== "undefined" && console.warn) {
          console.warn("radio_brgen_tunnel: animation frame failed, continuing", error)
        }
      }
      this._raf = requestAnimationFrame(loop)
    }
    loop()
  }

  destroy() {
    this._destroyed = true
    cancelAnimationFrame(this._raf)
    this.audioEngine.stop()
    if (this._tiltHandler) window.removeEventListener("deviceorientation", this._tiltHandler)
    this._boundHandlers.forEach(([target, event, handler]) => {
      const el = target === "overlay" ? this.overlay : target === "window" ? window : document
      if (el) el.removeEventListener(event, handler)
    })
  }
}

export { VisualEngine, MODES }
