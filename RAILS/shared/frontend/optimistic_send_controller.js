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
export default class extends Controller {
  static values = {
    // Filled from the server so the placeholder matches the real thing.
    handle: { type: String, default: "" },
    pendingLabel: { type: String, default: "sending…" },
    failedLabel: { type: String, default: "not sent — tap to retry" }
  }

  connect() {
    this.pending = null
    this.onStart = this.#start.bind(this)
    this.onEnd = this.#end.bind(this)
    this.element.addEventListener("turbo:submit-start", this.onStart)
    this.element.addEventListener("turbo:submit-end", this.onEnd)
  }

  disconnect() {
    this.element.removeEventListener("turbo:submit-start", this.onStart)
    this.element.removeEventListener("turbo:submit-end", this.onEnd)
    this.#clearPending()
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

    this.sentText = text
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
    if (!this.pending) return

    if (event.detail?.success === false) {
      // Put the text back rather than lose it, and say so.
      this.pending.querySelector("article")?.setAttribute("data-failed", "true")
      const note = this.pending.querySelector(".send-status")
      if (note) note.textContent = `· ${this.failedLabelValue}`
      const field = this.#field
      if (field && !field.value) field.value = this.sentText
      this.pending = null
      return
    }

    // Success: the real message arrives through the broadcast that renders
    // every message the same way. Drop the placeholder so there is exactly one.
    this.#clearPending()
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
