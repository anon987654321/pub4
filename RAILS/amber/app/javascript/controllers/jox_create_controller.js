import { Controller } from "@hotwired/stimulus"

// jOxVvNE create-button expand/collapse (exact class toggles from pen).
export default class extends Controller {
  static targets = ["button", "inner", "text", "menu", "item"]

  open = false

  toggle(event) {
    event.stopPropagation()
    this.open = !this.open
    this.#apply()
  }

  close() {
    if (!this.open) return
    this.open = false
    this.#apply()
  }

  #apply() {
    this.buttonTarget.classList.toggle("expanded", this.open)
    this.innerTarget.classList.toggle("expanded", this.open)
    this.textTarget.classList.toggle("expanded", this.open)
    this.menuTarget.classList.toggle("show", this.open)
    this.itemTargets.forEach((el) => el.classList.toggle("show", this.open))
  }
}
