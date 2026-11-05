import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["video"]
  static values = {
    orientation: { type: String, default: "landscape" },
    autoWakeLock: Boolean,
    autoOrientation: Boolean,
    progressUrl: String,
    // What the lock screen and a Bluetooth head unit show (Media Session).
    title: String,
    artist: String,
    artwork: String
  }

  connect() {
    this.#bindVideoEvents()
    if (this.autoWakeLockValue) this.#requestWakeLock()
    if (this.autoOrientationValue) this.#lockOrientation()
    this.#setupMediaSession()
    this.#bindNoteControls()
  }

  disconnect() {
    this.#reportProgress()
    this.#unbindVideoEvents()
    this.#releaseWakeLock()
    this.#unlockOrientation()
    if (this.boundNoteClick) document.removeEventListener("click", this.boundNoteClick)
  }

  async toggleFullscreen() {
    const container = this.element
    if (!document.fullscreenElement && container.requestFullscreen) {
      await container.requestFullscreen().catch(() => {})
      await this.#lockOrientation()
      await this.#requestWakeLock()
      return
    }

    if (document.fullscreenElement && document.exitFullscreen) {
      await document.exitFullscreen().catch(() => {})
      await this.#unlockOrientation()
      await this.#releaseWakeLock()
    }
  }

  async lockPortrait() {
    await this.#lockOrientation("portrait")
  }

  async lockLandscape() {
    await this.#lockOrientation("landscape")
  }

  async enableWakeLock() {
    await this.#requestWakeLock()
  }

  async disableWakeLock() {
    await this.#releaseWakeLock()
  }

  async maybeWakeLock() {
    if (!this.hasVideoTarget || !document.fullscreenElement) return
    await this.#requestWakeLock()
  }

  async releaseWakeLock() {
    await this.#releaseWakeLock()
  }

  // A note's time seeks the player, and "use current time" fills the note
  // form's timestamp field from it. Listened for on the document, not bound per
  // button: a note that arrives by broadcast, and the form a turbo-stream answer
  // swaps in, need no wiring of their own.
  #bindNoteControls() {
    if (!this.hasVideoTarget) return
    document.querySelectorAll("[data-tv-fill-timestamp]").forEach((button) => { button.hidden = false })

    this.boundNoteClick = (event) => {
      const seek = event.target.closest("[data-tv-seek-to]")
      if (seek) {
        this.videoTarget.currentTime = Number(seek.dataset.tvSeekTo) || 0
        return
      }

      const fill = event.target.closest("[data-tv-fill-timestamp]")
      if (!fill) return
      const field = document.getElementById(fill.dataset.tvFillTimestamp)
      if (field) field.value = Math.floor(this.videoTarget.currentTime || 0)
    }
    document.addEventListener("click", this.boundNoteClick)
  }

  // Media Session: lock-screen and Bluetooth controls for video, as the
  // playlist player has for audio. Metadata is set again on play, because the
  // playlist player in another tab may have claimed the session since.
  #setupMediaSession() {
    if (!("mediaSession" in navigator) || !this.hasVideoTarget) return
    const video = this.videoTarget

    const handlers = {
      play: () => video.play(),
      pause: () => video.pause(),
      seekbackward: (d) => { video.currentTime = Math.max(0, video.currentTime - (d.seekOffset || 10)) },
      seekforward: (d) => {
        video.currentTime = Math.min(video.duration || 0, video.currentTime + (d.seekOffset || 10))
      },
      seekto: (d) => { if (d.seekTime != null) video.currentTime = d.seekTime }
    }
    for (const [action, fn] of Object.entries(handlers)) {
      try { navigator.mediaSession.setActionHandler(action, fn) } catch (_) { /* unsupported action */ }
    }

    this.#updateMediaMetadata()
    this.boundSessionPlay = () => {
      this.#updateMediaMetadata()
      navigator.mediaSession.playbackState = "playing"
    }

    this.boundSessionPause = () => { navigator.mediaSession.playbackState = "paused" }
    video.addEventListener("play", this.boundSessionPlay)
    video.addEventListener("pause", this.boundSessionPause)
  }

  #updateMediaMetadata() {
    if (!window.MediaMetadata || !this.titleValue) return
    navigator.mediaSession.metadata = new window.MediaMetadata({
      title: this.titleValue,
      artist: this.artistValue,
      artwork: this.artworkValue ? [{ src: this.artworkValue, sizes: "1280x720", type: "image/webp" }] : []
    })
  }

  #bindVideoEvents() {
    if (!this.hasVideoTarget) return
    this.boundMaybeWakeLock = this.maybeWakeLock.bind(this)
    this.boundReleaseWakeLock = this.releaseWakeLock.bind(this)
    this.boundReportProgress = this.#reportProgress.bind(this)
    this.videoTarget.addEventListener("play", this.boundMaybeWakeLock)
    this.videoTarget.addEventListener("pause", this.boundReleaseWakeLock)
    this.videoTarget.addEventListener("ended", this.boundReleaseWakeLock)
    this.videoTarget.addEventListener("pause", this.boundReportProgress)
    this.videoTarget.addEventListener("ended", this.boundReportProgress)
    // A tab that is hidden and never restored fires no unload event on mobile;
    // visibilitychange is the only reliable point to flush watch time there.
    document.addEventListener("visibilitychange", this.boundVisibilityReport = () => {
      if (document.visibilityState === "hidden") this.#reportProgress()
    })
    document.addEventListener("fullscreenchange", this.boundFullscreenChange = () => {
      if (!document.fullscreenElement) this.#unlockOrientation()
    })
  }

  #unbindVideoEvents() {
    if (!this.hasVideoTarget) return
    this.videoTarget.removeEventListener("play", this.boundMaybeWakeLock)
    this.videoTarget.removeEventListener("pause", this.boundReleaseWakeLock)
    this.videoTarget.removeEventListener("ended", this.boundReleaseWakeLock)
    this.videoTarget.removeEventListener("pause", this.boundReportProgress)
    this.videoTarget.removeEventListener("ended", this.boundReportProgress)
    document.removeEventListener("visibilitychange", this.boundVisibilityReport)
    document.removeEventListener("fullscreenchange", this.boundFullscreenChange)
    if (this.boundSessionPlay) this.videoTarget.removeEventListener("play", this.boundSessionPlay)
    if (this.boundSessionPause) this.videoTarget.removeEventListener("pause", this.boundSessionPause)
  }

  // Report the furthest point reached, not currentTime: a viewer who watches to
  // 3:00 and then drags back to 0:10 to rewatch a bit has still watched three
  // minutes, and currentTime at pause would report ten seconds. The server takes
  // the max of what it has anyway, so the two agree.
  #reportProgress() {
    if (!this.progressUrlValue || !this.hasVideoTarget) return

    const reached = Math.max(this.furthest ?? 0, this.videoTarget.currentTime ?? 0)
    this.furthest = reached
    if (reached < 1 || reached === this.lastReported) return
    this.lastReported = reached

    const body = new FormData()
    body.append("watch_time_seconds", Math.round(reached))
    body.append("_method", "patch")
    const token = document.querySelector("meta[name='csrf-token']")?.content
    if (token) body.append("authenticity_token", token)

    // sendBeacon, not fetch: these fire while the page is going away, and the
    // browser cancels in-flight fetches on unload. It queues the request against
    // the browser rather than the document, so it survives.
    navigator.sendBeacon?.(this.progressUrlValue, body)
  }

  async #requestWakeLock() {
    if (!("wakeLock" in navigator) || this.wakeLockSentinel) return
    try {
      this.wakeLockSentinel = await navigator.wakeLock.request("screen")
      this.wakeLockSentinel.addEventListener("release", () => {
        this.wakeLockSentinel = null
      }, { once: true })
    } catch (_) {}
  }

  async #releaseWakeLock() {
    if (!this.wakeLockSentinel) return
    try { await this.wakeLockSentinel.release() } catch (_) {}
    this.wakeLockSentinel = null
  }

  async #lockOrientation(mode = this.orientationValue) {
    if (!screen.orientation?.lock) return
    try { await screen.orientation.lock(mode) } catch (_) {}
  }

  async #unlockOrientation() {
    if (!screen.orientation?.unlock) return
    try { screen.orientation.unlock() } catch (_) {}
  }
}
