import { Controller } from "@hotwired/stimulus"
import { fetchMissed, newestId, watchForCatchUp } from "controllers/catch_up"

// The comment thread on posts#show, live.
//
// A new comment is broadcast to everyone on the page, rendered for nobody and
// marked data-viewer-neutral (Comment#broadcast_to_thread). The person who
// wrote it also gets their own copy in the response to their form, carrying
// the delete button and reply box the neutral one lacks. Whichever lands
// second would replace the first, so a neutral copy is dropped when the
// comment is already on the page.
//
// Someone still reading above the end of the thread is not interrupted: a
// neutral comment is held back and counted on a "N new comments" chip, and
// pressing the chip lets them in and moves to the first of them.
//
// Comments written while the page was not listening are fetched on
// reconnect from PostCatchUpsController#comments.
export default class extends Controller {
  static targets = ["source", "thread", "chip"]
  static values = {
    sinceUrl: { type: String, default: "" },
    chipOne: { type: String, default: "" },
    chipOther: { type: String, default: "" },
  }

  connect() {
    this.held = []
    this.keepOwnCopy = this.keepOwnCopy.bind(this)
    document.addEventListener("turbo:before-stream-render", this.keepOwnCopy)
    this.stopWatching = watchForCatchUp(this.hasSourceTarget ? this.sourceTarget : null, () => this.catchUp())
  }

  disconnect() {
    document.removeEventListener("turbo:before-stream-render", this.keepOwnCopy)
    this.stopWatching?.()
  }

  catchUp() {
    fetchMissed(this.sinceUrlValue, newestId(this.element, "comment"))
  }

  keepOwnCopy(event) {
    const stream = event.target
    if (stream.getAttribute("action") !== "append" || !stream.hasAttribute("data-viewer-neutral")) return

    const incoming = stream.templateContent.firstElementChild
    if (incoming?.id && document.getElementById(incoming.id)) {
      event.preventDefault()
    } else if (!stream.hasAttribute("data-released") && this.readingAbove()) {
      event.preventDefault()
      this.held.push(stream.cloneNode(true))
      this.showChip()
    }
  }

  // The reader is above the end of the thread when its bottom edge is still
  // below the viewport's.
  readingAbove() {
    if (!this.hasThreadTarget || !this.hasChipTarget) return false
    const edge = this.threadTarget.getBoundingClientRect()
    return edge.bottom > window.innerHeight
  }

  showChip() {
    const count = this.held.length
    const label = count === 1 ? this.chipOneValue : this.chipOtherValue
    this.chipTarget.textContent = label.replace("%{count}", count)
    this.chipTarget.hidden = false
  }

  showNew() {
    const streams = this.held
    this.held = []
    this.chipTarget.hidden = true
    const firstId = streams[0]?.templateContent?.firstElementChild?.id
    streams.forEach((stream) => {
      stream.setAttribute("data-released", "")
      document.body.append(stream)
    })
    // Turbo renders a stream on the next frame.
    requestAnimationFrame(() => requestAnimationFrame(() => {
      const first = firstId && document.getElementById(firstId)
      if (!first) return
      first.scrollIntoView({ block: "center" })
      const article = first.querySelector("article")
      if (article) {
        article.setAttribute("tabindex", "-1")
        article.focus({ preventScroll: true })
      }
    }))
  }
}
