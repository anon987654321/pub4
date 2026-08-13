import { Controller } from "@hotwired/stimulus"

// The vertical feed: play whichever video is on screen, pause the rest, and
// report how much of each was actually watched.
//
// Scrolling and snapping are the browser's job (CSS scroll-snap). This decides
// what plays and what gets recorded, which is the part CSS cannot do.
export default class extends Controller {
  static targets = ["scroller", "item", "video", "soundButton"]
  static values = { signedIn: Boolean, nextUrl: String }

  connect() {
    this.muted = true
    this.events = new Map()   // item element -> { url, watched }
    this.timers = new Map()

    // 0.6 rather than 1.0: a snapped item is never quite fully visible during
    // the settle, and waiting for 1.0 leaves a video paused under the reader.
    this.visibility = new IntersectionObserver(
      entries => entries.forEach(entry => this.#onVisibility(entry)),
      { threshold: [0.6] }
    )
    this.itemTargets.forEach(item => this.visibility.observe(item))

    // Load the next screenful before the reader reaches the end, so the feed
    // never shows a bottom.
    if (this.hasNextUrlValue && this.nextUrlValue) this.#watchForEnd()
  }

  disconnect() {
    this.#reportAll()
    this.visibility?.disconnect()
    this.endWatcher?.disconnect()
    this.timers.forEach(id => clearInterval(id))
  }

  // Sound is opt-in: iOS refuses to autoplay anything unmuted, and a feed that
  // starts making noise on open is a feed people close.
  toggleSound(event) {
    this.muted = !this.muted
    this.videoTargets.forEach(video => { video.muted = this.muted })
    const button = event.currentTarget
    button.setAttribute("aria-pressed", String(!this.muted))
  }

  itemTargetConnected(item) {
    // Appended items (the next page) need observing too.
    this.visibility?.observe(item)
  }

  #onVisibility(entry) {
    const item = entry.target
    const video = item.querySelector("video")
    if (!video) return

    if (entry.isIntersecting) {
      video.muted = this.muted
      video.play().catch(() => {})
      this.#startTracking(item, video)
    } else {
      video.pause()
      this.#stopTracking(item, video)
    }
  }

  async #startTracking(item, video) {
    if (!this.signedInValue) return
    if (this.timers.has(item)) return

    // One view-event row per video, created the first time it is on screen.
    if (!this.events.has(item)) {
      this.events.set(item, { url: null, watched: 0 })
      try {
        const response = await fetch(item.dataset.viewEventsUrl, {
          method: "POST",
          headers: {
            "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content || "",
            "Accept": "application/json"
          },
          credentials: "same-origin"
        })
        if (response.ok) {
          const body = await response.json()
          this.events.get(item).url = body.url
        }
      } catch (_) { /* a feed that cannot record still has to play */ }
    }

    // Furthest point reached, sampled while it plays — a looping video's
    // currentTime returns to zero, so the max is the only honest number.
    const timer = setInterval(() => {
      const state = this.events.get(item)
      if (!state) return
      state.watched = Math.max(state.watched, video.currentTime || 0)
    }, 1000)
    this.timers.set(item, timer)
  }

  #stopTracking(item) {
    const timer = this.timers.get(item)
    if (timer) {
      clearInterval(timer)
      this.timers.delete(item)
    }
    this.#report(item)
  }

  #report(item) {
    const state = this.events.get(item)
    if (!state?.url || state.watched < 1) return

    const body = new FormData()
    body.append("watch_time_seconds", Math.round(state.watched))
    body.append("_method", "patch")
    const token = document.querySelector("meta[name='csrf-token']")?.content
    if (token) body.append("authenticity_token", token)
    // sendBeacon: these fire on scroll-away and on unload, and the browser
    // cancels in-flight fetches on unload.
    navigator.sendBeacon?.(state.url, body)
  }

  #reportAll() {
    this.events.forEach((_state, item) => this.#report(item))
  }

  #watchForEnd() {
    const last = this.itemTargets[this.itemTargets.length - 1]
    if (!last) return

    this.endWatcher = new IntersectionObserver(entries => {
      if (!entries.some(entry => entry.isIntersecting)) return
      this.endWatcher.disconnect()
      this.#loadMore()
    }, { threshold: [0.1] })
    this.endWatcher.observe(last)
  }

  async #loadMore() {
    try {
      const response = await fetch(this.nextUrlValue, {
        headers: { "Accept": "text/vnd.turbo-stream.html" },
        credentials: "same-origin"
      })
      if (!response.ok) return
      const html = await response.text()
      window.Turbo?.renderStreamMessage(html)
      // The appended items arrive with their own next-offset; re-arm on the
      // new last item.
      this.nextUrlValue = this.#bumpOffset(this.nextUrlValue)
      requestAnimationFrame(() => this.#watchForEnd())
    } catch (_) { /* the feed still holds what it has */ }
  }

  #bumpOffset(url) {
    try {
      const parsed = new URL(url, window.location.origin)
      const offset = parseInt(parsed.searchParams.get("offset") || "0", 10)
      parsed.searchParams.set("offset", String(offset + this.itemTargets.length))
      return parsed.pathname + parsed.search
    } catch (_) {
      return ""
    }
  }
}
