import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["video"]
  static values = {
    orientation: { type: String, default: "landscape" },
    autoWakeLock: Boolean,
    autoOrientation: Boolean,
    progressUrl: String
  }

  connect() {
    this.#bindVideoEvents()
    if (this.autoWakeLockValue) this.#requestWakeLock()
    if (this.autoOrientationValue) this.#lockOrientation()
  }

  disconnect() {
    this.#reportProgress()
    this.#unbindVideoEvents()
    this.#releaseWakeLock()
    this.#unlockOrientation()
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
  }

  // Report the furthest point reached, not currentTime: a viewer who watches to
  // 3:00 and then drags back to 0:10 to rewatch a bit has still watched three
  // minutes, and currentTime at pause would report ten seconds. The server takes
  // the max of what it has anyway, so the two agree.
  #reportProgress() {
    if (!this.progressUrlValue || !this.hasVideoTarget) return

    const reached = Math.max(this.furthest || 0, this.videoTarget.currentTime || 0)
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
