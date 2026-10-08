// Progressive disclosure for the bottom tab bar ("footer menu").
//
// Hidden by default so the feed owns the screen; reveal on scroll-up or the
// peel grip. Hide again on scroll-down. First visit gets a one-shot coach
// tip so the closed bar stays findable (NN/g progressive disclosure).
import { Controller } from "@hotwired/stimulus"
import { mayPrompt, YIELD_EVENT } from "pub4/onboarding"

const COACH_KEY = "pub4:tab-bar:coach-dismissed"

export default class extends Controller {
  static targets = ["bar", "peel", "coach"]
  static values = {
    storageKey: { type: String, default: "pub4:tab-bar:open" }
  }

  connect() {
    this.lastY = this.element.scrollTop
    this.ticking = false
    this.threshold = 8 // px of travel before reacting, avoids jitter at rest

    // Default closed (progressive disclosure). Session restore only if the
    // visitor already opened it this tab — not across sessions.
    this.#apply(this.#restore() !== true)
    this.#maybeShowCoach()

    this.onScroll = this.onScroll.bind(this)
    this.element.addEventListener("scroll", this.onScroll, { passive: true })

    // Step back for the install prompt without marking the coach dismissed —
    // the visitor has not seen it, so it is still owed to them on a later visit.
    this.onYield = () => {
      if (this.coachTimer) clearTimeout(this.coachTimer)
      this.#hideCoachUi()
    }
    window.addEventListener(YIELD_EVENT, this.onYield)
  }

  disconnect() {
    this.element.removeEventListener("scroll", this.onScroll)
    window.removeEventListener(YIELD_EVENT, this.onYield)
    if (this.coachTimer) clearTimeout(this.coachTimer)
  }

  // Peel grip / explicit affordance.
  reveal(event) {
    event?.preventDefault()
    this.#dismissCoach()
    this.#apply(false)
  }

  hide(event) {
    event?.preventDefault()
    this.#apply(true)
  }

  toggle(event) {
    event?.preventDefault()
    if (this.hidden) this.reveal(event)
    else this.hide(event)
  }

  dismissCoach(event) {
    event?.preventDefault()
    this.#dismissCoach()
  }

  get hidden() {
    return document.documentElement.classList.contains("chrome-hidden")
  }

  onScroll() {
    if (this.ticking) return
    this.ticking = true
    requestAnimationFrame(() => {
      const y = this.element.scrollTop
      const dy = y - this.lastY
      if (Math.abs(dy) > this.threshold) {
        // Scroll down → hide; scroll up → show. Stay hidden at the very top
        // until the visitor intentionally peels or scrolls back up mid-page.
        if (dy > 0 && y > this.threshold) this.#apply(true)
        else if (dy < 0) {
          this.#dismissCoach()
          this.#apply(false)
        }
        this.lastY = y
      }
      this.ticking = false
    })
  }

  #apply(hidden) {
    document.documentElement.classList.toggle("chrome-hidden", hidden)

    if (this.hasBarTarget) {
      this.barTarget.setAttribute("aria-hidden", hidden ? "true" : "false")
      if (hidden) this.barTarget.setAttribute("inert", "")
      else this.barTarget.removeAttribute("inert")
    }

    if (this.hasPeelTarget) {
      this.peelTarget.hidden = !hidden
      this.peelTarget.setAttribute("aria-expanded", hidden ? "false" : "true")
    }

    if (!hidden) this.#hideCoachUi()

    this.#persist(!hidden)
  }

  #maybeShowCoach() {
    if (!this.hasCoachTarget) return
    if (!this.hidden) return
    if (this.#coachDismissed()) return
    // Not on the first sitting, and never over the install prompt. "Menyen er
    // nederst" is worth nothing to someone still deciding whether they care
    // about the app; it used to fire 1.6s into the very first page view. See
    // pub4/onboarding for the ordering.
    if (!mayPrompt("menu_coach")) return

    // Delay so first paint isn't noisy; feed content lands first.
    this.coachTimer = setTimeout(() => {
      if (!this.hidden || this.#coachDismissed()) return
      if (!mayPrompt("menu_coach")) return

      this.coachTarget.hidden = false
      this.coachTarget.setAttribute("data-open", "1")
    }, 1600)
  }

  #dismissCoach() {
    try { window.localStorage.setItem(COACH_KEY, "1") } catch (_) {}
    this.#hideCoachUi()
  }

  #hideCoachUi() {
    if (!this.hasCoachTarget) return
    this.coachTarget.hidden = true
    this.coachTarget.removeAttribute("data-open")
  }

  #coachDismissed() {
    try { return window.localStorage.getItem(COACH_KEY) === "1" } catch (_) { return false }
  }

  #persist(open) {
    try { window.sessionStorage.setItem(this.storageKeyValue, open ? "1" : "0") } catch (_) {}
  }

  #restore() {
    try { return window.sessionStorage.getItem(this.storageKeyValue) === "1" } catch (_) { return false }
  }
}
