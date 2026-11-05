import { Controller } from "@hotwired/stimulus"
import { fetchMissed, newestId, watchForCatchUp } from "controllers/catch_up"

// New posts arrive without moving the page.
//
// The feed already had a realtime mechanism and it was the wrong one:
// Post#broadcast_live_refresh sent broadcast_refresh_to "posts", and a refresh
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
  static targets = ["pending", "chip", "count", "feed", "source"]
  // Both plural forms come from the server already translated, so the rule
  // stays I18n's rather than becoming an English one written in JavaScript.
  // brgen renders nb, and a hardcoded "new posts" here would be an English
  // string on a Norwegian page, which the suite treats as a defect.
  static values = {
    one: { type: String, default: "" },
    other: { type: String, default: "" },
    // PostCatchUpsController#feed, and the newest post id when the page was
    // rendered: the feed is ranked, so the newest post need not be on screen.
    sinceUrl: { type: String, default: "" },
    after: { type: Number, default: 0 },
    // People the reader has blocked. The city stream is rendered for nobody,
    // so their new cards arrive too and are dropped here.
    hiddenAuthors: { type: Array, default: [] },
    // The neighbourhood the feed is filtered to (0 for the whole city) and
    // whether it is the media wall. The stream carries the whole city, so a
    // staged card outside either is not a new post for this feed.
    neighborhood: { type: Number, default: 0 },
    media: { type: Boolean, default: false }
  }

  connect() {
    this.observer = new MutationObserver(() => this.refreshChip())
    this.observer.observe(this.pendingTarget, { childList: true })
    this.title = document.title
    this.titleOnReturn = () => this.writeTitle(document.hidden ? this.unseen().length : 0)
    document.addEventListener("visibilitychange", this.titleOnReturn)
    this.refreshChip()
    this.keepViewerState = this.keepViewerState.bind(this)
    document.addEventListener("turbo:before-stream-render", this.keepViewerState)
    this.stopWatching = watchForCatchUp(this.hasSourceTarget ? this.sourceTarget : null, () => this.catchUp())
  }

  disconnect() {
    this.observer?.disconnect()
    document.removeEventListener("turbo:before-stream-render", this.keepViewerState)
    document.removeEventListener("visibilitychange", this.titleOnReturn)
    // Only a title this wrote is put back; a page Turbo has moved on to has
    // its own already.
    if (document.title === this.written) document.title = this.title
    this.stopWatching?.()
  }

  // Posts the city stream carried while this page was not listening land in
  // the pending list, where the chip counts them like any other arrival.
  catchUp() {
    fetchMissed(this.sinceUrlValue, newestId(this.element, "post", this.afterValue))
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
    const count = this.unseen().length
    this.chipTarget.hidden = count === 0
    this.writeTitle(document.hidden ? count : 0)
    if (count === 0) return

    const label = count === 1 ? this.oneValue : this.otherValue
    this.countTarget.textContent = label.replace("%{count}", String(count))
  }

  // Staged cards the feed does not already show. A catch-up after a reconnect
  // can deliver a post the stream also carried, and counting it twice offers
  // the reader a post they can already see.
  unseen() {
    return Array.from(this.pendingTarget.children).filter((card) => !this.inFeed(card) && !this.hidden(card))
  }

  hidden(card) {
    const { authorId, neighborhoodId, media } = card.dataset
    const author = Number(authorId)
    if (author && this.hiddenAuthorsValue.includes(author)) return true
    if (this.neighborhoodValue && Number(neighborhoodId) !== this.neighborhoodValue) return true

    return this.mediaValue && media !== "true"
  }

  inFeed(card) {
    return Boolean(card.id && this.hasFeedTarget && this.feedTarget.querySelector(`[id="${card.id}"]`))
  }

  // A hidden tab says how many posts are waiting: "(3) Bergen". The title the
  // page was rendered with comes back once the tab is looked at again.
  writeTitle(count) {
    this.written = count > 0 ? `(${count}) ${this.title}` : this.title
    document.title = this.written
  }

  // Oldest first, so the batch keeps the order it arrived in once it is at the
  // top of the feed. Each card is wrapped in the <li> the list is built from —
  // the same wrapper home/_live_search_results puts around the same partial.
  //
  // An empty feed renders an empty state and no list to prepend into, so the
  // page is fetched again and arrives with the list built.
  show(event) {
    event?.preventDefault()
    if (!this.hasFeedTarget) return window.location.reload()

    const staged = this.unseen().reverse()
    Array.from(this.pendingTarget.children)
      .filter((card) => this.inFeed(card) || this.hidden(card))
      .forEach((card) => card.remove())

    let first = null
    for (const card of staged) {
      const row = document.createElement("li")
      row.appendChild(card)
      this.feedTarget.prepend(row)
      first = card
    }
    this.refreshChip()
    this.chipTarget.hidden = true
    this.reveal(first)
  }

  // The chip that held focus is gone, so focus moves to the newest card the
  // reader asked for, and the card is scrolled to where they can read it.
  reveal(card) {
    if (!card) return

    card.setAttribute("tabindex", "-1")
    card.focus({ preventScroll: true })
    card.scrollIntoView({ block: "start" })
  }
}
