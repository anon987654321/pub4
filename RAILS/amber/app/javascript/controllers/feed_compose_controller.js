import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "footer", "box"]

  connect() {
    this.collapsed = true
  }

  expand() {
    this.collapsed = false
    this.boxTarget.classList.add("amber-compose-box--expanded")
    if (this.hasFooterTarget) this.footerTarget.hidden = false
  }

  collapse(event) {
    if (this.inputTarget.value.trim().length > 0) return
    if (event?.relatedTarget && this.element.contains(event.relatedTarget)) return

    this.collapsed = true
    this.boxTarget.classList.remove("amber-compose-box--expanded")
    if (this.hasFooterTarget) this.footerTarget.hidden = true
  }
}