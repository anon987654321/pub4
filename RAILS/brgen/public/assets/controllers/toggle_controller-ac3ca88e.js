import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["item"]
  static values = { class: { type: String, default: "hidden" } }

  connect() {
    this.toggleClassName = this.element.dataset.toggleClass || this.classValue
  }

  toggle() {
    this.itemTargets.forEach(item => item.classList.toggle(this.toggleClassName))
  }
}
