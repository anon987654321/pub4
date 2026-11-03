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
// Comments written while the page was not listening are fetched on
// reconnect from PostCatchUpsController#comments.
export default class extends Controller {
  static targets = ["source"]
  static values = { sinceUrl: { type: String, default: "" } }

  connect() {
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
    if (incoming?.id && document.getElementById(incoming.id)) event.preventDefault()
  }
}
