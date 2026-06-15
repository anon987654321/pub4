import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static classes = ["toggle"]
  static targets = ["content"]

  toggle() {
    const cls = this.hasToggleClass ? this.toggleClass : "hidden"
    this.contentTargets.forEach(el => el.classList.toggle(cls))
  }
}