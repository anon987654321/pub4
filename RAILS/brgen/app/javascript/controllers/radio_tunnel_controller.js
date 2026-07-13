import { Controller } from "@hotwired/stimulus"
import { RadioBrgen } from "radio_brgen_tunnel"

export default class extends Controller {
  static targets = ["canvas", "overlay", "trackDisplay", "youtubePlayer", "cursor", "heading", "archaeology"]
  static values = { tracks: Array, heading: String }

  connect() {
    this.app = new RadioBrgen({
      canvas: this.canvasTarget,
      overlay: this.hasOverlayTarget ? this.overlayTarget : null,
      trackDisplay: this.hasTrackDisplayTarget ? this.trackDisplayTarget : null,
      youtubePlayer: this.hasYoutubePlayerTarget ? this.youtubePlayerTarget : null,
      cursor: this.hasCursorTarget ? this.cursorTarget : null,
      heading: this.hasHeadingTarget ? this.headingTarget : null,
      headingText: this.headingValue || "git dig · pub4/index.html",
      tracks: this.hasTracksValue ? this.tracksValue : undefined,
      onStart: () => this.revealArchaeology()
    })

    // Auto-start on playlist.brgen.no landing: immediately play tracks excavated from pub4/index.html
    // (warp tunnel visualizer + first track embed). Audio autoplay may still require a user gesture
    // per browser policy; the visualizer and track cycling run automatically.
    if (this.app && !this.app.isStarted) {
      this.app.start()
    }
  }

  disconnect() {
    this.app?.destroy()
    this.app = null
  }

  start(event) {
    event?.preventDefault()
    this.app?.start()
  }

  startKey(event) {
    if (!["Enter", "Space"].includes(event.code)) return
    event.preventDefault()
    this.start(event)
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