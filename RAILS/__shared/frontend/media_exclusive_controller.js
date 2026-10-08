import { Controller } from "@hotwired/stimulus"

// One sound at a time.
//
// The playlist player pauses its own <audio> and nothing else, the dilla
// sketches render bare <audio controls> that answer to no controller at all,
// and the radio tunnel keeps a third element. Start a sketch while a playlist
// is running and both play, because nothing in the page was ever told that
// audio is a shared resource.
//
// Listening on the document rather than wiring the players to each other: a
// native <audio controls> has no controller to wire, and any future one gets
// this for free. Capture phase is not a preference — `play` does not bubble,
// so a listener on the document only ever sees it on the way down.
//
// Two things are deliberately left alone. A muted element is not audible, so
// pausing it would stop a background loop nobody can hear for the benefit of
// nobody. And the radio tunnel's YouTube embed is a cross-origin iframe this
// cannot reach; the tunnel already silences its own iframe before starting an
// element, which is the half of that pair that can be fixed from here.
//
// A post's link embed (shared/_link_embed.html.erb) is the iframe this can
// reach, because it starts here. Its facade button calls playEmbed through
// data-action, which finds this controller on <body>, so a feed of
// twenty-five posts pays no controller instance of its own — the per-post cost
// FrontPageWeightTest budgets. A cross-origin player cannot be paused, so
// starting any sound puts a playing embed back to its facade, which stops it.
//
// The sandbox lets a player run and open its own links in a new tab, and
// withholds top navigation, so a player cannot move the page it sits on.
const EMBED_SANDBOX = "allow-scripts allow-same-origin allow-popups allow-popups-to-escape-sandbox allow-presentation"

export default class extends Controller {
  connect() {
    this.facades = new Map()
    this.pauseOthers = (event) => {
      const started = event.target
      if (!(started instanceof HTMLMediaElement)) return

      this.restoreEmbeds()
      this.pauseMedia(started)
    }

    document.addEventListener("play", this.pauseOthers, true)
  }

  disconnect() {
    document.removeEventListener("play", this.pauseOthers, true)
    this.facades.clear()
  }

  playEmbed({ currentTarget, params }) {
    const stage = currentTarget.closest(".link_embed_stage")
    const src = this.httpsUrl(params.src)
    if (!stage || !src) return

    this.restoreEmbeds()
    this.pauseMedia(null)
    this.facades.set(stage, Array.from(stage.childNodes))
    const frame = this.embedFrame(src, params)
    stage.replaceChildren(frame)
    frame.focus()
  }

  pauseMedia(except) {
    document.querySelectorAll("audio, video").forEach((el) => {
      if (el === except || el.paused || el.muted) return
      try {
        el.pause()
      } catch (_) {
        // A element detached mid-event refuses; nothing to recover.
      }
    })
  }

  embedFrame(src, { allow, title }) {
    const frame = document.createElement("iframe")
    frame.src = src
    frame.title = title ?? ""
    frame.allow = allow ?? ""
    frame.allowFullscreen = true
    frame.loading = "lazy"
    // YouTube refuses to play in a frame that sends no referrer at all.
    frame.referrerPolicy = "strict-origin-when-cross-origin"
    frame.setAttribute("sandbox", EMBED_SANDBOX)
    return frame
  }

  restoreEmbeds() {
    this.facades.forEach((nodes, stage) => {
      if (stage.isConnected) stage.replaceChildren(...nodes)
    })
    this.facades.clear()
  }

  // The server builds the address from the link's id. This only refuses what
  // is not HTTPS, so a malformed attribute cannot become a javascript: frame.
  httpsUrl(value) {
    try {
      const url = new URL(value)
      return url.protocol === "https:" ? url.href : null
    } catch (_) {
      return null
    }
  }
}
