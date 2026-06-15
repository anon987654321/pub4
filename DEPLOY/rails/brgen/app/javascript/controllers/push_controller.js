import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["badge"]
  static values = { vapidKey: String, subscribeUrl: String, unread: Number }

  async connect() {
    if (!("serviceWorker" in navigator) || !("PushManager" in window)) return
    this.observer = new MutationObserver(() => this.#syncBadge())
    this.observer.observe(this.element, { childList: true, subtree: true, characterData: true })
    this.#syncBadge()
    const reg = await navigator.serviceWorker.ready
    const existing = await reg.pushManager.getSubscription()
    if (existing) { await this.#save(existing); return }
    if (Notification.permission === "granted") await this.#subscribe(reg)
    if (Notification.permission === "default") this.#prompt(reg)
  }

  clearBadge() {
    navigator.clearAppBadge?.()
  }

  #syncBadge() {
    const n = Number(this.hasBadgeTarget ? this.badgeTarget.textContent.trim() : this.unreadValue)
    if (n > 0) navigator.setAppBadge?.(n)
    else navigator.clearAppBadge?.()
  }

  disconnect() {
    this.observer?.disconnect()
  }

  #prompt(reg) {
    // Defer permission request to a user gesture via the "Enable notifications" button if present.
    const btn = document.getElementById("push-enable-btn")
    if (!btn) return
    btn.hidden = false
    btn.addEventListener("click", async () => {
      const perm = await Notification.requestPermission()
      if (perm === "granted") { await this.#subscribe(reg); btn.hidden = true }
    }, { once: true })
  }

  async #subscribe(reg) {
    const sub = await reg.pushManager.subscribe({
      userVisibleOnly: true,
      applicationServerKey: this.#b64ToUint8(this.vapidKeyValue)
    })
    await this.#save(sub)
  }

  async #save(sub) {
    await fetch(this.subscribeUrlValue, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": document.querySelector("meta[name=csrf-token]")?.content
      },
      body: JSON.stringify(sub.toJSON())
    })
  }

  #b64ToUint8(b64) {
    const pad = "=".repeat((4 - b64.length % 4) % 4)
    const raw = atob((b64 + pad).replace(/-/g, "+").replace(/_/g, "/"))
    return Uint8Array.from(raw, c => c.charCodeAt(0))
  }
}
