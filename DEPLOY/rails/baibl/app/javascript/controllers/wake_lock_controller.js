import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  lock = null

  async connect() {
    if (!("wakeLock" in navigator)) return
    document.addEventListener("visibilitychange", this.#onVisibility)
    await this.#acquire()
  }

  disconnect() {
    document.removeEventListener("visibilitychange", this.#onVisibility)
    this.#release()
  }

  #onVisibility = () => {
    if (document.visibilityState === "visible") this.#acquire()
    else this.#release()
  }

  async #acquire() {
    try {
      this.lock = await navigator.wakeLock.request("screen")
    } catch (_) {}
  }

  async #release() {
    await this.lock?.release().catch(() => {})
    this.lock = null
  }
}