import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "title", "footer", "box"]
  static values = {
    expandedClass: { type: String, default: "compose-box--expanded" }
  }

  connect() {
    this.collapsed = true
    this.syncTitle()
  }

  expand() {
    this.collapsed = false
    this.boxTarget.classList.add(this.expandedClassValue)
    if (this.hasFooterTarget) this.footerTarget.hidden = false
  }

  collapse(event) {
    if (this.inputTarget.value.trim().length > 0) return
    if (event?.relatedTarget && this.element.contains(event.relatedTarget)) return

    this.collapsed = true
    this.boxTarget.classList.remove(this.expandedClassValue)
    if (this.hasFooterTarget) this.footerTarget.hidden = true
  }

  // Toggles a visible "attached" state on the enclosing <label> so picking a
  // file gives some feedback -- the <input> itself is visually-hidden.
  mediaSelected(event) {
    const label = event.target.closest("label")
    if (label) label.classList.toggle("compose-action--attached", event.target.files.length > 0)
  }

  syncTitle() {
    if (!this.hasTitleTarget) return

    const text = this.inputTarget.value.trim()
    const line = text.split("\n").find((row) => row.trim().length > 0) || text
    this.titleTarget.value = line.slice(0, 300)
  }
}
