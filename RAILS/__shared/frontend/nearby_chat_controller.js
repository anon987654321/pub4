import { Controller } from "@hotwired/stimulus"

// Ambient corner chat dock (brgen: #brgen lobby or #nearby when located).
// NN/g: status is always visible; location is progressive (explicit only);
// Escape closes; Enter sends from the composer.
const LOCATION_DENIED_KEY = "pub4:location-denied"

export default class extends Controller {
  static targets = ["panel", "tab", "log", "status", "tabLabel", "headerLabel", "mode"]
  static values = {
    storageKey: { type: String, default: "pub4:ambient-chat:open" },
    labelChat: { type: String, default: "chat" },
    labelNearby: { type: String, default: "nearby" },
    statusAsking: { type: String, default: "Asking for location…" },
    statusDenied: { type: String, default: "Location blocked — staying in #brgen. Enable location in the browser for #nearby." },
    statusTimeout: { type: String, default: "Location timed out — staying in #brgen." },
    statusUnavailable: { type: String, default: "Location unavailable — staying in #brgen." },
    statusBlocked: { type: String, default: "This page cannot read location — #brgen still works." },
    statusServer: { type: String, default: "Could not save location — try again." },
    statusNetwork: { type: String, default: "Network error saving location — try again." }
  }

  connect() {
    this.#apply(this.#restore(), { focus: false })
    this.#syncLabelsFromFrame()

    this.observer = new MutationObserver(() => {
      this.#pinToNewest()
      this.#syncLabelsFromFrame()
    })
    this.observer.observe(this.element, { childList: true, subtree: true })

    this.onDocumentClick = (event) => {
      if (this.open && !this.element.contains(event.target)) this.close()
    }
    this.onKeydown = (event) => {
      if (event.key !== "Escape" || !this.open) return
      this.close()
      if (this.hasTabTarget) this.tabTarget.focus()
    }
    this.onLocated = () => {
      this.#setStatus("")
      try { window.localStorage.removeItem(LOCATION_DENIED_KEY) } catch (_) {}
      this.#reloadFrame()
      this.#setTab("nearby")
    }
    this.onLocationError = (event) => this.#showLocationError(event?.detail?.reason)
    window.addEventListener("brgen:located", this.onLocated)
    window.addEventListener("brgen:location-error", this.onLocationError)

    document.addEventListener("click", this.onDocumentClick)
    document.addEventListener("keydown", this.onKeydown)
  }

  disconnect() {
    document.removeEventListener("click", this.onDocumentClick)
    document.removeEventListener("keydown", this.onKeydown)
    window.removeEventListener("brgen:located", this.onLocated)
    window.removeEventListener("brgen:location-error", this.onLocationError)
    this.observer?.disconnect()
    this.observer = null
  }

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

  show() {
    this.#apply(true, { focus: true })
    // Do not auto-prompt for GPS on open (progressive disclosure). Lobby
    // works without it; visitors opt in via "Use location".
  }

  close() { this.#apply(false, { focus: false }) }

  locate(event) {
    event?.preventDefault()
    try { window.localStorage.removeItem(LOCATION_DENIED_KEY) } catch (_) {}
    this.#setStatus(this.statusAskingValue)
    window.dispatchEvent(new CustomEvent("brgen:request-location"))
  }

  // Enter sends; Shift+Enter keeps a newline (standard chat affordance).
  composerKeydown(event) {
    if (event.key !== "Enter" || event.shiftKey) return
    if (event.isComposing) return
    event.preventDefault()
    const form = event.target.closest("form")
    if (!form) return
    if (typeof form.requestSubmit === "function") form.requestSubmit()
    else form.dispatchEvent(new Event("submit", { bubbles: true, cancelable: true }))
  }

  // Only count a real send toward install-value (not validation failures).
  markInstallValue(event) {
    if (event?.detail?.success === false) return
    window.dispatchEvent(new CustomEvent("pub4:install-value"))
  }

  get open() {
    return this.hasPanelTarget && !this.panelTarget.hasAttribute("hidden")
  }

  #showLocationError(reason) {
    if (reason === "denied") {
      try { window.localStorage.setItem(LOCATION_DENIED_KEY, "1") } catch (_) {}
    }
    const messages = {
      denied: this.statusDeniedValue,
      timeout: this.statusTimeoutValue,
      unavailable: this.statusUnavailableValue,
      blocked: this.statusBlockedValue,
      server: this.statusServerValue,
      network: this.statusNetworkValue
    }
    this.#setStatus(messages[reason] || this.statusUnavailableValue)
    this.#setTab("chat")
  }

  // Both label targets live inside this.element, which #observer watches with
  // {childList, subtree}. Writing textContent replaces the text node even when
  // the string is identical, so an unconditional assignment here is a mutation
  // that re-runs the observer that called us -- an unbreakable loop that pinned
  // a renderer at 100% CPU and hung every brgen system test forever. Nothing
  // caught it because ci.rb excludes test/system from the suite. Every write
  // reachable from the observer callback must therefore be a no-op when the
  // value has not changed.
  #setText(el, value) {
    if (el && el.textContent !== value) el.textContent = value
  }

  #setTab(mode) {
    const label = mode === "nearby" ? this.labelNearbyValue : this.labelChatValue
    if (this.hasTabLabelTarget) this.#setText(this.tabLabelTarget, label)
    if (this.hasHeaderLabelTarget) this.#setText(this.headerLabelTarget, label)
  }

  // After the turbo-frame loads lobby vs nearby, prefer the server mode line.
  #syncLabelsFromFrame() {
    const mode = this.hasModeTarget
      ? this.modeTarget
      : this.element.querySelector("[data-nearby-chat-target='mode']")
    if (!mode) return
    const strong = mode.querySelector("strong")
    if (!strong) return
    const text = strong.textContent?.trim()
    if (!text) return
    const label = text.replace(/^#/, "")
    if (this.hasTabLabelTarget) this.#setText(this.tabLabelTarget, label)
    if (this.hasHeaderLabelTarget) this.#setText(this.headerLabelTarget, label)
  }

  // Reachable from the observer callback via #showLocationError, so it carries
  // the same no-op-when-unchanged requirement as #setTab. See the note there.
  #setStatus(text) {
    if (!this.hasStatusTarget) return
    const next = text || ""
    this.#setText(this.statusTarget, next)
    if (this.statusTarget.hidden !== !next) this.statusTarget.hidden = !next
  }

  #apply(open, { focus }) {
    if (!this.hasPanelTarget) return
    if (open) this.panelTarget.removeAttribute("hidden")
    else this.panelTarget.setAttribute("hidden", "")
    if (this.hasTabTarget) this.tabTarget.setAttribute("aria-expanded", String(open))
    this.#persist(open)
    if (!open) return
    this.#pinToNewest()
    if (focus) this.#focusComposer()
  }

  #pinToNewest() {
    if (!this.open || !this.hasLogTarget) return
    this.logTarget.scrollTop = this.logTarget.scrollHeight
  }

  #focusComposer() {
    const field = this.element.querySelector("textarea, input[type=text]")
    if (field && !window.matchMedia("(hover: none)").matches) field.focus()
  }

  #persist(open) {
    try { window.sessionStorage.setItem(this.storageKeyValue, open ? "1" : "0") } catch (_) {}
  }

  #restore() {
    try { return window.sessionStorage.getItem(this.storageKeyValue) === "1" } catch (_) { return false }
  }
}
