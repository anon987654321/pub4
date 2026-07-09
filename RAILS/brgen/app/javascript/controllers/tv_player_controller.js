import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["video"]
  static values = {
    orientation: { type: String, default: "landscape" },
    autoWakeLock: Boolean,
    autoOrientation: Boolean
  }

  connect() {
    this.#bindVideoEvents()
    if (this.autoWakeLockValue) this.#requestWakeLock()
    if (this.autoOrientationValue) this.#lockOrientation()
  }

  disconnect() {
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
    this.videoTarget.addEventListener("play", this.boundMaybeWakeLock)
    this.videoTarget.addEventListener("pause", this.boundReleaseWakeLock)
    this.videoTarget.addEventListener("ended", this.boundReleaseWakeLock)
    document.addEventListener("fullscreenchange", this.boundFullscreenChange = () => {
      if (!document.fullscreenElement) this.#unlockOrientation()
    })
  }

  #unbindVideoEvents() {
    if (!this.hasVideoTarget) return
    this.videoTarget.removeEventListener("play", this.boundMaybeWakeLock)
    this.videoTarget.removeEventListener("pause", this.boundReleaseWakeLock)
    this.videoTarget.removeEventListener("ended", this.boundReleaseWakeLock)
    document.removeEventListener("fullscreenchange", this.boundFullscreenChange)
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
