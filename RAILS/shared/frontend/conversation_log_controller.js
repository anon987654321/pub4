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
// Grouping and the unread pill are here for the same reason as the stamping: a
// broadcast-rendered message has no idea what came before it, so "is this the
// same speaker as the line above?" can only be answered once it is in the DOM.
const GROUP_WINDOW_MS = 5 * 60 * 1000

export default class extends Controller {
  static values = { viewerId: String }

  connect() {
    this.unread = 0
    this.#stampAll()
    this.#group()
    this.#pinToNewest()

    this.observer = new MutationObserver((mutations) => {
      const added = mutations.flatMap((m) => Array.from(m.addedNodes))
      if (!added.length) return
      added.forEach((node) => { if (node.nodeType === Node.ELEMENT_NODE) this.#stamp(node) })
      this.#group()
      const wasAtTail = this.#atTail()
      this.#pinToNewest()
      if (!wasAtTail) {
        this.unread += added.filter((n) => n.nodeType === Node.ELEMENT_NODE).length
        this.#renderPill()
      }
    })
    this.observer.observe(this.element, { childList: true })

    this.onScroll = () => {
      if (this.#atTail()) { this.unread = 0; this.#renderPill() }
    }
    this.element.addEventListener("scroll", this.onScroll, { passive: true })
  }

  disconnect() {
    this.observer?.disconnect()
    this.observer = null
    this.element.removeEventListener("scroll", this.onScroll)
    this.pill?.remove()
    this.pill = null
  }

  // Jump back to the newest line. Bound from the pill.
  toTail() {
    this.element.scrollTop = this.element.scrollHeight
    this.unread = 0
    this.#renderPill()
  }

  // Consecutive lines from one speaker lose their repeated name/time header, so
  // a back-and-forth reads as two voices instead of a stack of identical
  // letterheads. Anything older than the window starts a fresh group even from
  // the same speaker, because a reply hours later is not the same breath.
  #group() {
    let prevSender = null
    let prevAt = 0

    Array.from(this.element.children).forEach((li) => {
      const art = li.querySelector("[data-sender-id]")
      if (!art) return
      const sender = art.dataset.senderId
      const at = Date.parse(art.querySelector("time")?.getAttribute("datetime") || "") || 0
      const continues =
        sender && sender === prevSender && prevAt && Math.abs(at - prevAt) < GROUP_WINDOW_MS

      art.dataset.grouped = continues ? "true" : "false"
      prevSender = sender
      prevAt = at
    })
  }

  #atTail() {
    const { scrollTop, scrollHeight, clientHeight } = this.element
    return scrollHeight - scrollTop - clientHeight < 80
  }

  #renderPill() {
    if (this.unread < 1) { this.pill?.remove(); this.pill = null; return }

    if (!this.pill) {
      this.pill = document.createElement("button")
      this.pill.type = "button"
      this.pill.className = "conversation_unread_pill"
      this.pill.addEventListener("click", () => this.toTail())
      this.element.insertAdjacentElement("afterend", this.pill)
    }
    const n = this.unread
    this.pill.textContent = `${n} new message${n === 1 ? "" : "s"} ↓`
    this.pill.setAttribute("aria-live", "polite")
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
    if (this.#atTail() || this.element.scrollTop === 0) {
      this.element.scrollTop = this.element.scrollHeight
    }
  }
}
