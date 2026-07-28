import { Controller } from "@hotwired/stimulus"

// IRC-style corner chat dock.
//
// Replaces @stimulus-components/reveal, which toggled a bare `.hidden`
// utility class. That class is only defined in brgen's own _nearby.scss, so
// on amber and bsdports the panel had no hiding rule at all: it rendered
// permanently expanded over the corner, and the :has(:not(.hidden)) rule then
// made the tab invisible, leaving no way to dismiss it. This controller owns
// the `hidden` attribute instead, and _shell_widgets.scss (shared, so every
// app gets it) carries the matching rule.
//
// Also does the three things a chat dock needs and reveal cannot do: keep
// aria-expanded truthful, pin the log to the newest line, and survive Turbo
// navigation so the room stays open while you browse.
export default class extends Controller {
  static targets = ["panel", "tab", "log"]
  static values = { storageKey: { type: String, default: "pub4:nearby-chat:open" } }

  connect() {
    this.#apply(this.#restore(), { focus: false })

    // The panel body is a lazy turbo-frame, so the log and composer arrive
    // after connect. Watching the whole widget subtree covers both the
    // initial frame load and every appended message.
    this.observer = new MutationObserver(() => this.#pinToNewest())
    this.observer.observe(this.element, { childList: true, subtree: true })

    this.onDocumentClick = (event) => {
      if (this.open && !this.element.contains(event.target)) this.close()
    }
    this.onKeydown = (event) => {
      if (event.key !== "Escape" || !this.open) return
      this.close()
      if (this.hasTabTarget) this.tabTarget.focus()
    }
    // The frame is server-rendered against "do we know where you are", which is
    // false at first paint because the geolocation prompt has not resolved yet.
    // Without this the panel showed "Share location to join" for the rest of the
    // session even once location had arrived.
    this.onLocated = () => this.#reloadFrame()
    window.addEventListener("brgen:located", this.onLocated, { once: true })

    document.addEventListener("click", this.onDocumentClick)
    document.addEventListener("keydown", this.onKeydown)
  }

  disconnect() {
    document.removeEventListener("click", this.onDocumentClick)
    document.removeEventListener("keydown", this.onKeydown)
    window.removeEventListener("brgen:located", this.onLocated)
    this.observer?.disconnect()
    this.observer = null
  }

  // Re-fetch by reassigning src: a turbo-frame only reloads when src changes or
  // .reload() is called, and .reload() is not in every Turbo version this fleet
  // runs.
  #reloadFrame() {
    const frame = this.element.querySelector("turbo-frame[src]")
    if (!frame) return

    if (typeof frame.reload === "function") frame.reload()
    else frame.setAttribute("src", frame.getAttribute("src"))
  }

  toggle(event) {
    event?.preventDefault()
    this.open ? this.close() : this.show()
  }

  show() { this.#apply(true, { focus: true }) }
  close() { this.#apply(false, { focus: false }) }

  // The "share location" CTA used to be a link to /nearby with turbo_frame:
  // "_top" — it closed the chat and navigated the whole page to go and grant a
  // permission the chat itself could have asked for. Ask here; the reload on
  // brgen:located then swaps the dead end for the room.
  locate(event) {
    event?.preventDefault()
    window.dispatchEvent(new CustomEvent("brgen:request-location"))
  }

  get open() {
    return this.hasPanelTarget && !this.panelTarget.hasAttribute("hidden")
  }

  #apply(open, { focus }) {
    if (!this.hasPanelTarget) return

    if (open) this.panelTarget.removeAttribute("hidden")
    else this.panelTarget.setAttribute("hidden", "")

    // reveal never touched this, so the tab reported "collapsed" to screen
    // readers no matter what the panel was doing.
    if (this.hasTabTarget) this.tabTarget.setAttribute("aria-expanded", String(open))

    this.#persist(open)
    if (!open) return

    this.#pinToNewest()
    if (focus) this.#focusComposer()
  }

  // A chat log that opens scrolled to the oldest line is unusable; so is one
  // that stays put when a message arrives.
  #pinToNewest() {
    if (!this.open || !this.hasLogTarget) return
    this.logTarget.scrollTop = this.logTarget.scrollHeight
  }

  #focusComposer() {
    const field = this.element.querySelector("textarea, input[type=text]")
    // Focusing on a touch keyboard pops it over the panel unprompted.
    if (field && !window.matchMedia("(hover: none)").matches) field.focus()
  }

  #persist(open) {
    try {
      window.sessionStorage.setItem(this.storageKeyValue, open ? "1" : "0")
    } catch {
      /* private mode / storage disabled — open state just won't survive nav */
    }
  }

  #restore() {
    try {
      return window.sessionStorage.getItem(this.storageKeyValue) === "1"
    } catch {
      return false
    }
  }
}
