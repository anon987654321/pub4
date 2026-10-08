import { Controller } from "@hotwired/stimulus"

// Heartbeat so the room knows who still has it open.
//
// The count itself arrives over the conversation's Turbo stream, so this only
// ever posts -- it never reads a response. Beat interval must stay comfortably
// under ChannelPresence::TTL (45s) or readers flicker out between beats.
const BEAT_MS = 20_000

export default class extends Controller {
  static values = { url: String }

  connect() {
    if (!this.urlValue) return

    this.#beat()
    this.timer = setInterval(() => this.#beat(), BEAT_MS)

    // Stop beating while the tab is hidden: a backgrounded tab is not somebody
    // sitting in the room, and browsers throttle timers there anyway, which
    // would make the count lie in both directions.
    this.onVisibility = () => {
      if (document.hidden) { this.#stopTimer() } else if (!this.timer) {
        this.#beat()
        this.timer = setInterval(() => this.#beat(), BEAT_MS)
      }
    }
    document.addEventListener("visibilitychange", this.onVisibility)

    // Leave promptly rather than waiting out the TTL. keepalive lets the request
    // outlive the page; pagehide fires on mobile background/close where unload
    // does not.
    this.onLeave = () => this.#leave()
    window.addEventListener("pagehide", this.onLeave)
    document.addEventListener("turbo:before-visit", this.onLeave)
  }

  disconnect() {
    this.#stopTimer()
    document.removeEventListener("visibilitychange", this.onVisibility)
    window.removeEventListener("pagehide", this.onLeave)
    document.removeEventListener("turbo:before-visit", this.onLeave)
    this.#leave()
  }

  #stopTimer() {
    if (this.timer) clearInterval(this.timer)
    this.timer = null
  }

  #token() {
    return document.querySelector('meta[name="csrf-token"]')?.content || ""
  }

  #beat() {
    fetch(this.urlValue, {
      method: "POST",
      headers: { "X-CSRF-Token": this.#token() },
      credentials: "same-origin",
      keepalive: true
    }).catch(() => {})
  }

  #leave() {
    if (!this.urlValue || this.left) return
    this.left = true
    fetch(this.urlValue, {
      method: "DELETE",
      headers: { "X-CSRF-Token": this.#token() },
      credentials: "same-origin",
      keepalive: true
    }).catch(() => {})
  }
}
