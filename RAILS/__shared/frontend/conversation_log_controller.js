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
  static values = {
    viewerId: String,
    unreadOne: { type: String, default: "%{count} new message ↓" },
    unreadOther: { type: String, default: "%{count} new messages ↓" },
    todayLabel: { type: String, default: "Today" },
    yesterdayLabel: { type: String, default: "Yesterday" },
    locale: { type: String, default: "en" }
  }

  connect() {
    this.unread = 0
    this.#stampAll()
    this.#dayBreaks()
    this.#group()
    this.#pinToNewest()

    this.observer = new MutationObserver((mutations) => {
      const added = mutations.flatMap((m) => Array.from(m.addedNodes))
      if (!added.length) return
      added.forEach((node) => { if (node.nodeType === Node.ELEMENT_NODE) this.#stamp(node) })
      // #dayBreaks writes children of the element this observer watches, so it
      // would wake itself forever. Suspending is the whole guard.
      this.observer.disconnect()
      this.#dayBreaks()
      this.observer.observe(this.element, { childList: true })
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

    // Tap-to-reveal for the reaction picker. On a touch viewport the picker was
    // permanently visible (`@media (hover: none) { opacity: 1 }`), which put a
    // 44px row of seven buttons under every single line — the exact cost the
    // reactions partial says it exists to avoid. Bubbles were tall enough to
    // hide it; an IRC transcript is not.
    //
    // One delegated listener on the log, not a controller per message: there
    // are already 271 controller instances on a brgen page and a per-line
    // controller would scale with the transcript. Tapping the line is the
    // affordance, so this adds no chrome of its own. Hover/focus keeps working
    // untouched for pointer and keyboard users.
    this.onLineTap = (event) => {
      if (!this.#isTouch()) return
      // Let real controls do their job — chips, the picker itself, links.
      if (event.target.closest("button, a, input, textarea, select")) return

      const li = event.target.closest("li")
      if (!li || li.parentElement !== this.element) return
      const open = li.dataset.reactionsOpen === "true"
      this.#closeAllPickers()
      if (!open) li.dataset.reactionsOpen = "true"
    }
    this.element.addEventListener("click", this.onLineTap)

    this.onKeydown = (event) => { if (event.key === "Escape") this.#closeAllPickers() }
    this.element.addEventListener("keydown", this.onKeydown)
  }

  disconnect() {
    this.observer?.disconnect()
    this.observer = null
    this.element.removeEventListener("scroll", this.onScroll)
    this.element.removeEventListener("click", this.onLineTap)
    this.element.removeEventListener("keydown", this.onKeydown)
    this.pill?.remove()
    this.pill = null
  }

  #isTouch() {
    return window.matchMedia?.("(hover: none)")?.matches ?? false
  }

  #closeAllPickers() {
    this.element.querySelectorAll('li[data-reactions-open="true"]')
      .forEach((li) => { delete li.dataset.reactionsOpen })
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
  // The date, once, where the day turns.
  //
  // Derived here rather than in the partial for the same reason grouping is: a
  // message rendered by Turbo::Streams::ActionBroadcastJob has no idea what came
  // before it, and a thread left open across midnight has to grow a separator
  // without a reload. Both facts are already in the DOM — every message carries
  // its own <time datetime> — so this needs nothing from the server.
  //
  // Separators are removed and re-derived on every pass rather than patched. The
  // list is a conversation, not a table: it is short enough that recomputing is
  // cheaper than reasoning about which break a late-arriving message invalidated.
  #dayBreaks() {
    this.element.querySelectorAll(":scope > .day-break").forEach((el) => el.remove())

    let prevDay = null

    Array.from(this.element.children).forEach((li) => {
      const iso = li.querySelector("[data-sender-id] time")?.getAttribute("datetime")
      if (!iso) return

      const at = new Date(iso)
      if (Number.isNaN(at.getTime())) return

      const day = at.toDateString()
      if (day === prevDay) return

      prevDay = day
      li.insertAdjacentElement("beforebegin", this.#dayBreakFor(at))
    })
  }

  // Today and yesterday by name, the week by weekday, anything older by date.
  // The ladder is what makes the label worth its line: "onsdag" locates a
  // message in a way "22.08.2026" does not, right up until the week turns over
  // and it stops being unambiguous.
  #dayBreakFor(at) {
    const li = document.createElement("li")
    li.className = "day-break"
    li.setAttribute("role", "separator")

    const full = at.toLocaleDateString(this.localeValue, {
      weekday: "long", day: "numeric", month: "long", year: "numeric"
    })
    li.setAttribute("aria-label", full)

    const label = document.createElement("span")
    label.textContent = this.#dayLabel(at)
    li.append(label)
    return li
  }

  #dayLabel(at) {
    const midnight = (d) => new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime()
    const days = Math.round((midnight(new Date()) - midnight(at)) / 86400000)

    if (days === 0) return this.todayLabelValue
    if (days === 1) return this.yesterdayLabelValue
    if (days > 1 && days < 7) return at.toLocaleDateString(this.localeValue, { weekday: "long" })

    return at.toLocaleDateString(this.localeValue, { day: "numeric", month: "long", year: "numeric" })
  }

  #group() {
    let prevSender = null
    let prevAt = 0

    Array.from(this.element.children).forEach((li) => {
      const art = li.querySelector("[data-sender-id]")
      // A day break ends the run: two lines from the same person a minute apart
      // across midnight are not one utterance, and grouping them would hide the
      // header directly under the separator that just announced a new day.
      if (!art) { prevSender = null; prevAt = 0; return }
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
    const template = n === 1 ? this.unreadOneValue : this.unreadOtherValue
    this.pill.textContent = template.replace("%{count}", String(n))
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
