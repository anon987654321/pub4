import { Controller } from "@hotwired/stimulus"

// Marks who sent each message, and keeps the log pinned to the newest line.
//
// Why this can't be done in the partial alone: Message#broadcasts_to renders
// messages/_message inside Turbo::Streams::ActionBroadcastJob, a background
// job with no request and therefore no Current.user. Every live-appended
// message fell through to data-from="peer" — so your own messages appeared as
// though a stranger had sent them the moment they arrived over the wire, and
// only looked right after a reload.
//
// The server stamps data-sender-id (viewer-independent, so it is correct in a
// job) and the log carries the viewer's id from the in-request render.
export default class extends Controller {
  static values = { viewerId: String }

  connect() {
    this.#stampAll()
    this.#pinToNewest()

    this.observer = new MutationObserver((mutations) => {
      const added = mutations.flatMap((m) => Array.from(m.addedNodes))
      if (!added.length) return
      added.forEach((node) => { if (node.nodeType === Node.ELEMENT_NODE) this.#stamp(node) })
      this.#pinToNewest()
    })
    this.observer.observe(this.element, { childList: true })
  }

  disconnect() {
    this.observer?.disconnect()
    this.observer = null
  }

  #stampAll() {
    this.element.querySelectorAll("[data-sender-id]").forEach((el) => this.#stamp(el))
  }

  #stamp(node) {
    if (!this.viewerIdValue) return
    const targets = node.matches?.("[data-sender-id]")
      ? [node]
      : Array.from(node.querySelectorAll?.("[data-sender-id]") || [])

    targets.forEach((el) => {
      el.dataset.from = el.dataset.senderId === this.viewerIdValue ? "self" : "peer"
    })
  }

  // Only follow the tail if the reader is already at it — yanking the view
  // down while someone scrolls back through history is worse than not
  // following at all.
  #pinToNewest() {
    const { scrollTop, scrollHeight, clientHeight } = this.element
    const atTail = scrollHeight - scrollTop - clientHeight < 80
    if (atTail || scrollTop === 0) this.element.scrollTop = scrollHeight
  }
}
