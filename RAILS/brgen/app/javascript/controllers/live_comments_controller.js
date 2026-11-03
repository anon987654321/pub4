import { Controller } from "@hotwired/stimulus"

// The comment thread on posts#show, live.
//
// A new comment is broadcast to everyone on the page, rendered for nobody and
// marked data-viewer-neutral (Comment#broadcast_to_thread). The person who
// wrote it also gets their own copy in the response to their form, carrying
// the delete button and reply box the neutral one lacks. Whichever lands
// second would replace the first, so a neutral copy is dropped when the
// comment is already on the page.
export default class extends Controller {
  connect() {
    this.keepOwnCopy = this.keepOwnCopy.bind(this)
    document.addEventListener("turbo:before-stream-render", this.keepOwnCopy)
  }

  disconnect() {
    document.removeEventListener("turbo:before-stream-render", this.keepOwnCopy)
  }

  keepOwnCopy(event) {
    const stream = event.target
    if (stream.getAttribute("action") !== "append" || !stream.hasAttribute("data-viewer-neutral")) return

    const incoming = stream.templateContent.firstElementChild
    if (incoming?.id && document.getElementById(incoming.id)) event.preventDefault()
  }
}
