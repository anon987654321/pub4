import { Controller } from "@hotwired/stimulus"

// New posts arrive without moving the page.
//
// The feed already had a realtime mechanism and it was the wrong one:
// Post#broadcast_live_refresh sends broadcast_refresh_to "posts", and a refresh
// replaces the list under whoever is reading it. Somebody three screens down a
// thread gets pulled back to the top by a stranger posting. That is the first
// thing BRGEN-105 asks not to do.
//
// So the broadcast lands in a hidden staging list instead, and this counts what
// is in it and offers it. Nothing moves until the reader taps.
//
// The observer watches the staging list and writes only to the feed and the
// chip — never to what it observes. That separation is deliberate: writing to
// the observed node from inside its own MutationObserver is what produced the
// 100%-CPU spin in 951dcd00d, and optimistic_send_controller carries the same
// warning for the same reason.
export default class extends Controller {
  static targets = ["pending", "chip", "count", "feed"]
  // Both plural forms come from the server already translated, so the rule
  // stays I18n's rather than becoming an English one written in JavaScript.
  // brgen renders nb, and a hardcoded "new posts" here would be an English
  // string on a Norwegian page, which the suite treats as a defect.
  static values = {
    one: { type: String, default: "" },
    other: { type: String, default: "" }
  }

  connect() {
    this.observer = new MutationObserver(() => this.refreshChip())
    this.observer.observe(this.pendingTarget, { childList: true })
    this.refreshChip()
    this.keepViewerState = this.keepViewerState.bind(this)
    document.addEventListener("turbo:before-stream-render", this.keepViewerState)
  }

  disconnect() {
    this.observer?.disconnect()
    document.removeEventListener("turbo:before-stream-render", this.keepViewerState)
  }

  // An edited card, or one whose link embed has resolved, arrives whole from
  // the city stream, rendered for nobody (Post#broadcast_card_replacement marks
  // it data-viewer-neutral). The reader's own vote rail, repost button and quote
  // form — the elements marked data-viewer-state — are carried over from the
  // card it replaces, so an edit never takes anyone's vote or buttons away. A
  // replace from the reader's own request (a vote) is theirs already and is left
  // alone.
  keepViewerState(event) {
    const stream = event.target
    if (stream.getAttribute("action") !== "replace" || !stream.hasAttribute("data-viewer-neutral")) return

    const id = stream.getAttribute("target") ?? ""
    const card = document.getElementById(id)
    if (!card || !this.element.contains(card)) return

    const own = card.querySelectorAll("[data-viewer-state]")
    const kept = new Map(Array.from(own, (node) => [node.dataset.viewerState, node]))
    const render = event.detail.render
    event.detail.render = async (element) => {
      await render(element)
      document.getElementById(id)?.querySelectorAll("[data-viewer-state]").forEach((node) => {
        const mine = kept.get(node.dataset.viewerState)
        if (mine) node.replaceWith(mine)
      })
    }
  }

  // The chip is the whole indicator: a count and a way to act on it. It hides
  // itself at zero rather than rendering an empty state, because a control that
  // says "0 new posts" is asking to be read and then ignored.
  refreshChip() {
    const count = this.pendingTarget.children.length
    this.chipTarget.hidden = count === 0
    if (count === 0) return

    const label = count === 1 ? this.oneValue : this.otherValue
    this.countTarget.textContent = label.replace("%{count}", String(count))
  }

  // Oldest first, so the batch keeps the order it arrived in once it is at the
  // top of the feed. Each card is wrapped in the <li> the list is built from —
  // the same wrapper home/_live_search_results puts around the same partial.
  show(event) {
    event?.preventDefault()
    const staged = Array.from(this.pendingTarget.children).reverse()

    for (const card of staged) {
      const row = document.createElement("li")
      row.appendChild(card)
      this.feedTarget.prepend(row)
    }
    this.refreshChip()
    this.chipTarget.hidden = true
  }
}
