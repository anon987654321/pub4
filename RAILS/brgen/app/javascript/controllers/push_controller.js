import { Controller } from "@hotwired/stimulus"
import { mayPrompt, YIELD_EVENT } from "pub4/onboarding"

// The browser's permission sheet is asked for once, in context: right after the
// reader's first post, comment or message, when "tell me when someone answers"
// is the obvious next thing, and never on arrival, before there is anything to
// be told about.
const ASKED_KEY = "pub4:push:context-asked"
// A create that someone can answer: a post, a comment, a message.
const ANSWERABLE = /\/(posts|comments|messages)$/

export default class extends Controller {
  static values = { vapidKey: String, subscribeUrl: String, unread: Number, native: Boolean, nativeUrl: String }

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
    // Heard at the start, on the document, and at the end on the form itself:
    // a composer replaced by its own stream answer is out of the document by
    // the time turbo:submit-end fires, and an event on a detached form reaches
    // only the form's own listeners.
    this.onSubmitStart = (event) => {
      const form = event.target
      if (!this.#answerable(form)) return
      form.addEventListener("turbo:submit-end", (end) => { if (end.detail?.success) this.#ask() }, { once: true })
    }
    document.addEventListener("turbo:submit-start", this.onSubmitStart)
    this.#wirePrompt()

    // The iOS shell is a WKWebView with no Push API; it registers for APNs through
    // its pub4Push bridge instead, and only when the server can send through APNs.
    if (this.nativeValue && window.webkit?.messageHandlers?.pub4Push) return this.#native()

    if (!("serviceWorker" in navigator) || !("PushManager" in window)) return
    this.#syncBadge()
    this.webAskable = Notification.permission === "default"
    const reg = await navigator.serviceWorker.ready
    this.registration = reg
    const existing = await reg.pushManager.getSubscription()
    if (existing) { await this.#save(existing); return }
    if (Notification.permission === "granted") await this.#subscribe(reg)
  }

  disconnect() {
    document.removeEventListener("turbo:load", this.onNavigate)
    document.removeEventListener("turbo:submit-start", this.onSubmitStart)
    window.removeEventListener(YIELD_EVENT, this.onYield)
    document.removeEventListener("click", this.onPromptClick)
    if (this.onNativeToken) window.removeEventListener("pub4:native-push-token", this.onNativeToken)
  }

  clearBadge() {
    navigator.clearAppBadge?.()
  }

  #syncBadge() {
    const n = this.unreadValue
    if (n > 0) navigator.setAppBadge?.(n)
    else navigator.clearAppBadge?.()
  }

  // The shell answers pub4:native-push-status with the iOS permission state, and
  // sends pub4:native-push-token whenever iOS hands it a token: at once on a
  // launch where the reader already allowed it, after the sheet otherwise. The
  // same button and onboarding gate as the web path.
  #native() {
    this.onNativeToken = (event) => this.#saveNative(event.detail)
    window.addEventListener("pub4:native-push-token", this.onNativeToken)

    window.addEventListener("pub4:native-push-status", (event) => {
      this.nativeAskable = event.detail?.status === "notDetermined"
    }, { once: true })
    window.webkit.messageHandlers.pub4Push.postMessage({ action: "status" })
  }

  async #saveNative({ token, environment } = {}) {
    if (!token) return
    await fetch(this.nativeUrlValue, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": document.querySelector("meta[name=csrf-token]")?.content
      },
      body: JSON.stringify({ token, environment })
    })
  }

  // A POST whose form creates something answerable. A PATCH or a DELETE rides
  // a POST with a _method field, and is not a first anything.
  #answerable(form) {
    if (!(form instanceof HTMLFormElement)) return false
    if (form.querySelector("input[name=_method]")) return false
    return ANSWERABLE.test(new URL(form.action, window.location.href).pathname)
  }

  #ask() {
    const prompt = this.#promptElement
    if (!prompt || !prompt.hidden || !(this.webAskable || this.nativeAskable)) return
    if (localStorage.getItem(ASKED_KEY)) return
    // Consent first, and never on top of the install prompt.
    if (!mayPrompt("push_context")) return

    prompt.hidden = false
  }

  // The prompt is data-turbo-permanent, so it outlives the redirect that
  // usually follows the post that raised it. Its buttons are read by one
  // delegated listener, which goes with this controller, rather than wired on
  // an element that stays while controllers come and go.
  #wirePrompt() {
    this.onYield = () => { if (this.#promptElement) this.#promptElement.hidden = true }
    window.addEventListener(YIELD_EVENT, this.onYield)
    this.onPromptClick = async (event) => {
      if (event.target.closest("#push-prompt [data-push-later]")) return this.#answered()
      if (!event.target.closest("#push-prompt #push-enable-button")) return

      this.#answered()
      if (this.nativeAskable) return window.webkit.messageHandlers.pub4Push.postMessage({ action: "request" })

      const perm = await Notification.requestPermission()
      if (perm === "granted" && this.registration) await this.#subscribe(this.registration)
    }
    document.addEventListener("click", this.onPromptClick)
  }

  #answered() {
    try { localStorage.setItem(ASKED_KEY, "1") } catch { /* private mode: asked again next time */ }
    this.#promptElement.hidden = true
  }

  get #promptElement() {
    return document.getElementById("push-prompt")
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
