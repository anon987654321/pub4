// Hotkey controller — vim-style j/k navigation, Enter open, / search, ? help
// Triangle feeds: .feed-card (brgen), .feed-post (amber), listings, comments.
// NN/g #6/#7: recognition over recall — first-visit coach once; ? always shows help.
import { Controller } from "@hotwired/stimulus"

const ITEM_SEL = [
  ".feed-card",
  ".feed-post",
  ".comment.comment_item",
  ".post",
  ".listing",
  ".swipe-card",
  "article.card",
  ".card"
].join(", ")

const COACH_KEY = "pub4:hotkey-coach:dismissed"

export default class extends Controller {
  static targets = ["item"]
  static values = {
    help: { type: String, default: "j/k · ↓↑ nav · Enter open · / search · n new · esc clear · ? help" },
    coach: { type: String, default: "Keyboard: press ? anytime for shortcuts (j/k to move, / to search)." },
    coachDismiss: { type: String, default: "Got it" }
  }

  connect() {
    this.boundHandle = this.handleKey.bind(this)
    document.addEventListener("keydown", this.boundHandle)
    this.index = -1
    this.prefersReduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches
    // First visit: brief coach after layout settles (tab-bar pattern).
    requestAnimationFrame(() => this.#maybeShowCoach())
  }

  disconnect() {
    document.removeEventListener("keydown", this.boundHandle)
  }

  handleKey(e) {
    const tag = document.activeElement?.tagName
    const editable =
      ["INPUT", "TEXTAREA", "SELECT"].includes(tag) ||
      document.activeElement?.isContentEditable

    // Cmd/Ctrl-K reaches the search from inside a field too — that is the point of
    // it, and why every app that has one binds both. It came from bsdports' local
    // search_hotkey_controller, which bound / and Cmd-K on the ports index only; the
    // rest of bsdports had no search shortcut at all because the layout never
    // registered a hotkey controller.
    if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "k") {
      e.preventDefault()
      this.#focusSearch()
      return
    }

    if (editable) {
      // Allow Escape to blur composer fields back to the feed.
      if (e.key === "Escape") document.activeElement.blur()
      return
    }

    if (e.key === "j" || e.key === "ArrowDown") {
      e.preventDefault()
      this.move(1)
    } else if (e.key === "k" || e.key === "ArrowUp") {
      e.preventDefault()
      this.move(-1)
    } else if (e.key === "Enter") {
      if (this.#openFocused(e)) e.preventDefault()
    } else if (e.key === "/") {
      e.preventDefault()
      this.#focusSearch()
    } else if (e.key === "?") {
      e.preventDefault()
      this.showHelp()
    } else if (e.key.toLowerCase() === "n" && !e.metaKey && !e.ctrlKey) {
      const newLink = document.querySelector('a[href*="/new"], [data-hotkey-new]')
      if (newLink) {
        e.preventDefault()
        newLink.click()
      }
    } else if (e.key === "Escape") {
      document.querySelectorAll(".hotkey-focus").forEach((el) => el.classList.remove("hotkey-focus"))
      this.index = -1
      this.#hideCoach()
    }
  }

  move(delta) {
    const items = this.#items()
    if (!items.length) return
    if (this.index < 0) this.index = delta > 0 ? 0 : items.length - 1
    else this.index = Math.max(0, Math.min(items.length - 1, this.index + delta))
    const el = items[this.index]
    const behavior = this.prefersReduced ? "auto" : "smooth"
    el.scrollIntoView({ behavior, block: "center" })
    document.querySelectorAll(".hotkey-focus").forEach((n) => n.classList.remove("hotkey-focus"))
    el.classList.add("hotkey-focus")
    if (!el.hasAttribute("tabindex")) el.setAttribute("tabindex", "-1")
    try { el.focus({ preventScroll: true }) } catch (_) { /* older browsers */ }
  }

  #items() {
    if (this.hasItemTarget) return this.itemTargets
    return Array.from(document.querySelectorAll(ITEM_SEL)).filter((el) => {
      // Prefer outermost feed cards; skip nested chrome inside a card.
      return !el.parentElement?.closest(ITEM_SEL)
    })
  }

  #openFocused(e) {
    const focused = document.querySelector(".hotkey-focus") || document.activeElement
    if (!focused || !focused.closest) return false
    const card = focused.closest(ITEM_SEL) || (focused.matches?.(ITEM_SEL) ? focused : null)
    if (!card) return false
    const link =
      card.querySelector("a.feed-card-name, a.link-inherit, .feed-card-text a, a[href]")
    if (link) {
      link.click()
      return true
    }
    return false
  }

  #focusSearch() {
    const field = document.querySelector(
      'input[type=search], input[name=q], .widget-search input, .nav-search-input, [data-hotkey-search]'
    )
    if (field) {
      field.focus()
      if (typeof field.select === "function") field.select()
    }
  }

  showHelp() {
    const existing = document.querySelector(".hotkey-help")
    if (existing) {
      existing.remove()
      return
    }
    const help = document.createElement("div")
    help.className = "hotkey-help"
    help.setAttribute("role", "status")
    help.setAttribute("aria-live", "polite")
    help.textContent = this.helpValue
    document.body.appendChild(help)
    setTimeout(() => { if (help?.parentNode) help.parentNode.removeChild(help) }, 2800)
  }

  #maybeShowCoach() {
    try {
      if (localStorage.getItem(COACH_KEY) === "1") return
    } catch (_) {
      return
    }
    // Only coach when there is something to navigate (feed surface).
    if (this.#items().length < 1) return

    // ...and only where there is a keyboard to coach about. The copy is
    // "Keyboard: press ? anytime for shortcuts (j/k to move, / to search)", and
    // it was showing on a 390px touch viewport with no keyboard, no ? key and no
    // j/k — verified on live brgen.no. A coarse pointer with no hover is a touch
    // device; the shortcuts themselves stay bound either way, for a paired
    // keyboard.
    const fine = window.matchMedia("(hover: hover) and (pointer: fine)")
    if (fine.matches === false) return

    const coach = document.createElement("div")
    coach.className = "hotkey-coach"
    coach.setAttribute("role", "status")
    coach.setAttribute("aria-live", "polite")
    coach.innerHTML = ""
    const text = document.createElement("p")
    text.className = "hotkey-coach-text"
    text.textContent = this.coachValue
    const btn = document.createElement("button")
    btn.type = "button"
    btn.className = "hotkey-coach-dismiss"
    btn.textContent = this.coachDismissValue
    btn.addEventListener("click", () => {
      try { localStorage.setItem(COACH_KEY, "1") } catch (_) { /* private mode */ }
      coach.remove()
    })
    coach.appendChild(text)
    coach.appendChild(btn)
    document.body.appendChild(coach)
    this._coachEl = coach
    // Auto-dismiss after long read window; still marks dismissed so we don't nag.
    setTimeout(() => {
      if (!coach.parentNode) return
      try { localStorage.setItem(COACH_KEY, "1") } catch (_) { /* */ }
      coach.remove()
    }, 8000)
  }

  #hideCoach() {
    if (this._coachEl?.parentNode) this._coachEl.remove()
  }
}
