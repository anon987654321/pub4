import { Controller } from "@hotwired/stimulus"
import { useIntersection } from "stimulus-use"
import StimulusReflex from "stimulus_reflex"

export default class extends Controller {
  static values = { reflex: String }

  connect() {
    StimulusReflex.register(this)
    useIntersection(this)
  }

  appear() {
    if (this.element.dataset.loading === "true") return
    if (!this.element.dataset.nextPage) return

    this.element.dataset.loading = "true"
    const reflex = this.reflexValue || this.element.dataset.reflex
    this.stimulate(reflex, this.element)
  }
}