import { Controller } from "@hotwired/stimulus"
import { RadioBrgen } from "radio_brgen_tunnel"

export default class extends Controller {
  static targets = ["canvas", "overlay", "trackDisplay", "youtubePlayer", "heading", "archaeology"]
  static values = { tracks: Array, heading: String, autoStart: { type: Boolean, default: true } }

  connect() {
    this.app = new RadioBrgen({
      canvas: this.canvasTarget,
      overlay: this.hasOverlayTarget ? this.overlayTarget : null,
      trackDisplay: this.hasTrackDisplayTarget ? this.trackDisplayTarget : null,
      youtubePlayer: this.hasYoutubePlayerTarget ? this.youtubePlayerTarget : null,
      heading: this.hasHeadingTarget ? this.headingTarget : null,
      headingText: this.headingValue || null,
      tracks: this.hasTracksValue ? this.tracksValue : undefined,
      onStart: () => this.revealArchaeology()
    })

    if (this.autoStartValue && this.app && !this.app.isStarted) {
      // Fire on next tick so iframe + canvas layout settle; mirrors MASTER face
      // embed autostart (no click-to-start overlay on first paint).
      this._autoTimer = window.setTimeout(() => this.#tryAutoStart(), 0)
    }

    // Browsers may block YouTube autoplay without a gesture. Any first pointer
    // or key on the tunnel starts audio if auto-start was muted/blocked.
    this._onFirstGesture = () => this.#ensureStarted()
    this.element.addEventListener("pointerdown", this._onFirstGesture, { capture: true })
    this.element.addEventListener("keydown", this._onFirstGesture, { capture: true })
  }

  disconnect() {
    if (this._autoTimer) window.clearTimeout(this._autoTimer)
    if (this._fallbackTimer) window.clearTimeout(this._fallbackTimer)
    this.element.removeEventListener("pointerdown", this._onFirstGesture, { capture: true })
    this.element.removeEventListener("keydown", this._onFirstGesture, { capture: true })
    this.app?.destroy()
    this.app = null
  }

  start(event) {
    event?.preventDefault()
    this.#ensureStarted()
  }

  startKey(event) {
    if (!["Enter", "Space"].includes(event.code)) return
    event.preventDefault()
    this.start(event)
  }

  #tryAutoStart() {
    if (!this.app || this.app.isStarted) return
    this.app.start()
    // If autoplay is blocked, re-show the overlay so one tap still unlocks sound.
    this._fallbackTimer = window.setTimeout(() => {
      if (!this.app?.audioEngine?.isPlaying && this.hasOverlayTarget) {
        this.overlayTarget.hidden = false
        this.overlayTarget.querySelector(".radio-start-hint")?.replaceChildren(
          document.createTextNode("tap if silent")
        )
      }
    }, 1800)
  }

  #ensureStarted() {
    if (!this.app) return
    if (this._fallbackTimer) window.clearTimeout(this._fallbackTimer)
    if (!this.app.isStarted) this.app.start()
    else {
      // Already started visually but maybe muted by policy — re-assert play.
      this.app.audioEngine?.setUserInteracted?.()
      this.app.audioEngine?.start?.()
    }
    if (this.hasOverlayTarget) this.overlayTarget.hidden = true
  }

  revealArchaeology() {
    if (this.hasArchaeologyTarget) this.archaeologyTarget.hidden = false
  }

  openLibrary() {
    document.getElementById("radio-library")?.removeAttribute("hidden")
  }

  closeLibrary() {
    document.getElementById("radio-library")?.setAttribute("hidden", "hidden")
  }
}
