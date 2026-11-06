import { Controller } from "@hotwired/stimulus"

// Show the message the instant it is sent, not when the server gets round to it.
//
// Measured on the ambient chat widget before this existed: between pressing
// send and anything at all changing on screen, 2746ms / 4859ms / 5340ms across
// three consecutive sends. The composer kept the text, the log did not move,
// and there was no pending state anywhere — so the correct read of the UI was
// "nothing happened". People retype or press send again.
//
// Most of that is round-trip: the message is written, then broadcast back
// through Message#broadcasts_to, and only the broadcast paints. That is the
// right architecture — one code path renders every message, wherever it came
// from — but it means the sender waits for the same trip as everyone else with
// no local echo. This adds the echo and nothing else: the server stays the
// single source of truth for what a message IS.
//
// Deliberately NOT done inside conversation_log_controller's MutationObserver.
// That observer watches the log and writing to the log from inside it is what
// produced the 100%-CPU spin in 951dcd00d. This controller owns the FORM and
// only ever touches the log from a submit event.
//
// A send that did not get through stays on screen as a failed line and is
// sent again — by a tap on it, or by itself when the connection comes back —
// rather than being lost or retyped. Every attempt carries a token (the form's
// client_token field, when it has one) that the retries share, so a send whose
// answer was lost on the way back is recognised by the server and not written
// twice. The token changes when the text does, and after a send that landed.
export default class extends Controller {
  static targets = ["token"]
  static values = {
    // Filled from the server so the placeholder matches the real thing.
    handle: { type: String, default: "" },
    pendingLabel: { type: String, default: "sending…" },
    failedLabel: { type: String, default: "not sent — tap to retry" },
    offlineLabel: { type: String, default: "offline — sends when you are back" }
  }

  connect() {
    this.pending = null
    this.failed = null
    this.failedText = null
    this.retryOnReconnect = false
    this.attemptText = null
    this.onStart = this.#start.bind(this)
    this.onEnd = this.#end.bind(this)
    this.onInput = this.#inputChanged.bind(this)
    this.onOnline = this.#reconnected.bind(this)
    this.onTap = this.#tapped.bind(this)
    this.element.addEventListener("turbo:submit-start", this.onStart)
    this.element.addEventListener("turbo:submit-end", this.onEnd)
    this.element.addEventListener("input", this.onInput)
    window.addEventListener("online", this.onOnline)
    this.#log?.addEventListener("click", this.onTap)
    this.#log?.addEventListener("keydown", this.onTap)
    this.#rotateToken()
  }

  disconnect() {
    this.element.removeEventListener("turbo:submit-start", this.onStart)
    this.element.removeEventListener("turbo:submit-end", this.onEnd)
    this.element.removeEventListener("input", this.onInput)
    window.removeEventListener("online", this.onOnline)
    this.#log?.removeEventListener("click", this.onTap)
    this.#log?.removeEventListener("keydown", this.onTap)
    this.#clearPending()
    this.failed?.remove()
    this.failed = null
  }

  get #field() {
    return this.element.querySelector("textarea, input[type=text]")
  }

  get #log() {
    // The widget's log and the full channel log are both .conversation-log.
    return this.element.closest(".nearby-chat-widget-panel, body")
      ?.querySelector(".conversation-log")
  }

  #start() {
    const field = this.#field
    const text = field?.value?.trim()
    if (!text) return

    // The line from an earlier failed attempt gives way to this one; the retry
    // is the same message under the same token, not a second line.
    this.failed?.remove()
    this.failed = null

    this.sentText = text
    this.attemptText = text
    // Clear immediately: the box emptying is the strongest signal that the tap
    // registered, and it is the one thing that used to take five seconds.
    field.value = ""
    field.dispatchEvent(new Event("input", { bubbles: true }))

    const log = this.#log
    if (!log) return

    const li = document.createElement("li")
    li.setAttribute("role", "listitem")
    li.dataset.optimistic = "true"
    li.innerHTML = `<article data-from="self" aria-busy="true">
      <header><span class="msg-nick">${this.#escape(this.handleValue)}</span>
      <span class="send-status">· ${this.#escape(this.pendingLabelValue)}</span></header>
      <p></p></article>`
    li.querySelector("p").textContent = text
    log.appendChild(li)
    log.scrollTop = log.scrollHeight
    this.pending = li
  }

  #end(event) {
    if (!this.pending) {
      // A send with no text to echo (a photo, a voice note) still used its token.
      if (event.detail?.success !== false) this.#rotateToken()
      return
    }

    if (event.detail?.success === false) {
      // Keep the line, say why, and put the text back rather than lose it. No
      // fetchResponse means the request never got an answer: a dropped
      // connection, which is the case worth retrying by itself.
      const offline = !event.detail?.fetchResponse
      const article = this.pending.querySelector("article")
      article?.setAttribute("data-failed", "true")
      article?.removeAttribute("aria-busy")
      if (article) article.tabIndex = 0
      const note = this.pending.querySelector(".send-status")
      const label = offline && navigator.onLine === false ? this.offlineLabelValue : this.failedLabelValue
      if (note) note.textContent = `· ${label}`
      const field = this.#field
      if (field && !field.value) field.value = this.sentText
      this.failed = this.pending
      this.failedText = this.sentText
      this.retryOnReconnect = offline
      this.pending = null
      return
    }

    // Success: the real message arrives through the broadcast that renders
    // every message the same way. Drop the placeholder so there is exactly one.
    this.failedText = null
    this.retryOnReconnect = false
    this.attemptText = null
    this.#clearPending()
    this.#rotateToken()
  }

  // A new attempt needs a new name. Editing the text of a failed send makes it a
  // different message, and under the old token the server would answer with the
  // first one and drop the edit.
  #inputChanged() {
    const value = this.#field?.value?.trim() ?? ""
    // The box emptying after a send is not an edit: #start clears it, and
    // rotating here would give the retry a different name from the attempt.
    if (value === "") return
    if (this.attemptText !== null && value !== this.attemptText) {
      this.attemptText = null
      this.#rotateToken()
    }
  }

  // A tap, or Enter/Space from the keyboard, on the failed line.
  #tapped(event) {
    if (event.type === "keydown" && event.key !== "Enter" && event.key !== " ") return

    const line = event.target.closest?.("li[data-optimistic='true'] article[data-failed='true']")
    if (!line) return

    event.preventDefault()
    this.#retry()
  }

  #reconnected() {
    if (this.failed && this.retryOnReconnect) this.#retry()
  }

  #retry() {
    const field = this.#field
    if (!field || !this.failedText) return
    // Only the failed text goes back, and only if the box is free: a retry must
    // not overwrite something the person has since started typing.
    if (field.value.trim() && field.value.trim() !== this.failedText) return

    field.value = this.failedText
    this.element.requestSubmit?.()
  }

  #rotateToken() {
    if (!this.hasTokenTarget) return
    this.tokenTarget.value = crypto.randomUUID?.() ?? `${Date.now()}-${Math.random().toString(36).slice(2)}`
  }

  #clearPending() {
    this.pending?.remove()
    this.pending = null
  }

  #escape(value) {
    const d = document.createElement("div")
    d.textContent = value ?? ""
    return d.innerHTML
  }
}
