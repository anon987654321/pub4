import { Controller } from "@hotwired/stimulus"

// Ambient corner chat dock (brgen: #brgen lobby or #nearby when located).
const LOCATION_DENIED_KEY = "pub4:location-denied"

export default class extends Controller {
  static targets = ["panel", "tab", "log", "status", "tabLabel", "headerLabel", "mode"]
  static values = { storageKey: { type: String, default: "pub4:ambient-chat:open" } }

  connect() {
    this.#apply(this.#restore(), { focus: false })

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
    // Soft-ask location only if not permanently denied and still on lobby.
    if (this.#wantsLocation() && !this.#locationDenied()) {
      this.#setStatus("Optional: share location for #nearby…")
      window.dispatchEvent(new CustomEvent("brgen:request-location"))
    }
  }

  close() { this.#apply(false, { focus: false }) }

  locate(event) {
    event?.preventDefault()
    try { window.localStorage.removeItem(LOCATION_DENIED_KEY) } catch (_) {}
    this.#setStatus("Asking for location…")
    window.dispatchEvent(new CustomEvent("brgen:request-location"))
  }

  // Fired after a successful widget send — install prompt can offer PWA earlier.
  markInstallValue() {
    window.dispatchEvent(new CustomEvent("pub4:install-value"))
  }

  get open() {
    return this.hasPanelTarget && !this.panelTarget.hasAttribute("hidden")
  }

  #wantsLocation() {
    // Lobby shows "Use location"; geo room shows refresh.
    return !!this.element.querySelector("[data-action*='nearby-chat#locate']")
  }

  #locationDenied() {
    try { return window.localStorage.getItem(LOCATION_DENIED_KEY) === "1" } catch (_) { return false }
  }

  #showLocationError(reason) {
    if (reason === "denied") {
      try { window.localStorage.setItem(LOCATION_DENIED_KEY, "1") } catch (_) {}
    }
    const messages = {
      denied: "Location blocked — staying in #brgen. Enable location in the browser for #nearby.",
      timeout: "Location timed out — staying in #brgen.",
      unavailable: "Location unavailable — staying in #brgen.",
      blocked: "This page cannot read location — #brgen still works.",
      server: "Could not save location — try again.",
      network: "Network error saving location — try again."
    }
    this.#setStatus(messages[reason] || messages.unavailable)
    this.#setTab("chat")
  }

  #setTab(mode) {
    const label = mode === "nearby" ? "nearby" : "chat"
    if (this.hasTabLabelTarget) this.tabLabelTarget.textContent = label
    if (this.hasHeaderLabelTarget) this.headerLabelTarget.textContent = label
  }

  #setStatus(text) {
    if (!this.hasStatusTarget) return
    this.statusTarget.textContent = text || ""
    this.statusTarget.hidden = !text
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
