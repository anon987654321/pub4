// Hotkey controller — vim-style j/k navigation, Enter open, / search, ? help
// Triangle feeds: .feed-card (brgen), .feed-post (amber), listings, comments.
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

export default class extends Controller {
  static targets = ["item"]

  connect() {
    this.boundHandle = this.handleKey.bind(this)
    document.addEventListener("keydown", this.boundHandle)
    this.index = -1
    this.prefersReduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches
  }

  disconnect() {
    document.removeEventListener("keydown", this.boundHandle)
  }

  handleKey(e) {
    const tag = document.activeElement?.tagName
    const editable =
      ["INPUT", "TEXTAREA", "SELECT"].includes(tag) ||
      document.activeElement?.isContentEditable
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
    help.textContent = "j/k · ↓↑ nav · Enter open · / search · n new · esc clear · ? help"
    document.body.appendChild(help)
    setTimeout(() => { if (help?.parentNode) help.parentNode.removeChild(help) }, 2200)
  }
}
