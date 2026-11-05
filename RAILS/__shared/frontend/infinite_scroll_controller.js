import { Controller } from "@hotwired/stimulus"
import { useIntersection } from "stimulus-use"
import StimulusReflex from "stimulus_reflex"

// A page that never arrives must not stop the feed. data-loading went to "true"
// before the reflex and only the reflex's own reply set it back, so an error, a
// halted reflex or a dropped socket left it "true" for good and the feed stopped
// without a word. Now a failure or TIMEOUT_MS of silence clears it, says so in
// the status line, and leaves the Load more button as the way to try again.
const TIMEOUT_MS = 15000

export default class extends Controller {
  static targets = ["status"]
  static values = { reflex: String, loading: String, failed: String }

  connect() {
    StimulusReflex.register(this)
    useIntersection(this)
    this.cleared = (event) => {
      if (event.detail?.id && event.detail.id !== this.element.id) return
      this.settle()
      this.announce("")
    }
    document.addEventListener("infinite-scroll:updated", this.cleared)
  }

  disconnect() {
    clearTimeout(this.timer)
    document.removeEventListener("infinite-scroll:updated", this.cleared)
  }

  // Called by the intersection observer and by the Load more button. After a
  // failure only the button retries: scrolling past a sentinel that just failed
  // would otherwise ask again in a tight loop.
  appear(event) {
    if (this.element.dataset.loading === "true") return
    if (!this.element.dataset.nextPage) return
    if (this.failed && !(event instanceof Event)) return

    this.failed = false
    this.element.dataset.loading = "true"
    this.announce(this.loadingValue)
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.fail(), TIMEOUT_MS)
    const reflex = this.reflexValue || this.element.dataset.reflex
    this.stimulate(reflex, this.element)
  }

  // StimulusReflex's generic lifecycle callbacks for a reflex that did not land.
  reflexError() { this.fail() }
  reflexHalted() { this.fail() }
  reflexForbidden() { this.fail() }

  fail() {
    if (this.element.dataset.loading !== "true") return

    this.settle()
    this.failed = true
    this.announce(this.failedValue)
  }

  settle() {
    const { dataset } = this.element
    clearTimeout(this.timer)
    dataset.loading = "false"
  }

  announce(text) {
    if (this.hasStatusTarget) this.statusTarget.textContent = text
  }
}
