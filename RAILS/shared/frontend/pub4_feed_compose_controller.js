import { Controller } from "@hotwired/stimulus"

// Unified feed compose expand/collapse for brgen + amber.
// Uses compose-box / compose-box--expanded classes (see shared/_x_compose.scss).
export default class extends Controller {
  static targets = ["input", "title", "footer", "box"]

  connect() {
    this.collapsed = true
    this.syncTitle()
  }

  expand() {
    this.collapsed = false
    this.boxTarget.classList.add("compose-box--expanded")
    if (this.hasFooterTarget) this.footerTarget.hidden = false
  }

  collapse(event) {
    if (this.inputTarget.value.trim().length > 0) return
    if (event?.relatedTarget && this.element.contains(event.relatedTarget)) return

    this.collapsed = true
    this.boxTarget.classList.remove("compose-box--expanded")
    if (this.hasFooterTarget) this.footerTarget.hidden = true
  }

  syncTitle() {
    if (!this.hasTitleTarget) return

    const text = this.inputTarget.value.trim()
    const line = text.split("\n").find((row) => row.trim().length > 0) || text
    this.titleTarget.value = line.slice(0, 300)
  }
}