import { Controller } from "@hotwired/stimulus"
import { useIntersection } from "stimulus-use"
import StimulusReflex from "stimulus_reflex"

export default class extends Controller {
  static targets = ["status"]
  static values = { reflex: String, loading: String }

  connect() {
    StimulusReflex.register(this)
    useIntersection(this)
    this.cleared = () => this.announce("")
    document.addEventListener("infinite-scroll:updated", this.cleared)
  }

  disconnect() {
    document.removeEventListener("infinite-scroll:updated", this.cleared)
  }

  // Called by the intersection observer and by the Load more button.
  appear() {
    if (this.element.dataset.loading === "true") return
    if (!this.element.dataset.nextPage) return

    this.element.dataset.loading = "true"
    this.announce(this.loadingValue)
    const reflex = this.reflexValue || this.element.dataset.reflex
    this.stimulate(reflex, this.element)
  }

  announce(text) {
    if (this.hasStatusTarget) this.statusTarget.textContent = text
  }
}
