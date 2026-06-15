import { Controller } from "@hotwired/stimulus"
import { listSyncQueue, dequeueSync } from "pwa/offline_store"

export default class extends Controller {
  static values = { replayUrl: String }

  connect() {
    window.addEventListener("online", this.#replay)
    navigator.serviceWorker?.addEventListener("message", this.#onMessage)
    if (navigator.onLine) this.#replay()
  }

  disconnect() {
    window.removeEventListener("online", this.#replay)
    navigator.serviceWorker?.removeEventListener("message", this.#onMessage)
  }

  #onMessage = event => {
    if (event.data?.type === "REPLAY_SYNC_QUEUE") this.#replay()
  }

  #replay = async () => {
    const queue = await listSyncQueue()
    for (const item of queue) {
      try {
        const response = await fetch(item.url, {
          method: item.method || "POST",
          headers: {
            "Content-Type": "application/json",
            "X-CSRF-Token": document.querySelector("meta[name=csrf-token]")?.content || ""
          },
          body: JSON.stringify(item.body || {})
        })
        if (response.ok) await dequeueSync(item.id)
      } catch (_) {
        // Stay queued until next reconnect/sync event
      }
    }
  }
}