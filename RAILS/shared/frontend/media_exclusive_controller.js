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
export default class extends Controller {
  connect() {
    this.pauseOthers = (event) => {
      const started = event.target
      if (!(started instanceof HTMLMediaElement)) return

      document.querySelectorAll("audio, video").forEach((el) => {
        if (el === started || el.paused || el.muted) return
        try {
          el.pause()
        } catch (_) {
          // A element detached mid-event refuses; nothing to recover.
        }
      })
    }

    document.addEventListener("play", this.pauseOthers, true)
  }

  disconnect() {
    document.removeEventListener("play", this.pauseOthers, true)
  }
}
