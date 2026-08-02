import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { vapidKey: String, subscribeUrl: String, unread: Number }

  async connect() {
    // This element is data-turbo-permanent, so connect() runs once per full
    // load and unreadValue never refreshes. Reading a DM therefore has to clear
    // the badge from a navigation event rather than from a reconnect.
    //
    // The two views that want this used to write `turbo:load->push#clearBadge`
    // into content_for :body_attrs — which the layout never yielded, and which
    // could not have worked if it had: Stimulus resolves an action against the
    // element and its ancestors, and <body> is this controller's ancestor, not
    // its descendant. They now set data-push-seen and this reads it.
    this.onNavigate = () => { if (document.body.dataset.pushSeen === "true") this.clearBadge() }
    document.addEventListener("turbo:load", this.onNavigate)

    if (!("serviceWorker" in navigator) || !("PushManager" in window)) return
    this.#syncBadge()
    const reg = await navigator.serviceWorker.ready
    const existing = await reg.pushManager.getSubscription()
    if (existing) { await this.#save(existing); return }
    if (Notification.permission === "granted") await this.#subscribe(reg)
    if (Notification.permission === "default") this.#prompt(reg)
  }

  disconnect() {
    document.removeEventListener("turbo:load", this.onNavigate)
  }

  clearBadge() {
    navigator.clearAppBadge?.()
  }

  #syncBadge() {
    const n = this.unreadValue
    if (n > 0) navigator.setAppBadge?.(n)
    else navigator.clearAppBadge?.()
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
