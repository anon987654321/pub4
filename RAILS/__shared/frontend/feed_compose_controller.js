import { Controller } from "@hotwired/stimulus"

// Two shapes share this controller.
//
// brgen opens the composer as a <dialog>: the resting row is a thin trigger and
// the writing surface floats over the feed, so the feed does not reflow when you
// start writing. amber still expands in place, so expand/collapse stay.
export default class extends Controller {
  static targets = ["input", "title", "footer", "box", "dialog"]
  static values = {
    expandedClass: { type: String, default: "compose-box--expanded" }
  }

  connect() {
    this.collapsed = true
    this.syncTitle()
    // Successful posts count as install-prompt "value" (earlier PWA offer).
    this._onSubmitEnd = (event) => {
      if (event.detail?.success === false) return
      window.dispatchEvent(new CustomEvent("pub4:install-value"))
    }
    this.element.addEventListener("turbo:submit-end", this._onSubmitEnd)
  }

  disconnect() {
    if (this._onSubmitEnd) {
      this.element.removeEventListener("turbo:submit-end", this._onSubmitEnd)
    }
  }

  // --- dialog shape (brgen) ---

  open() {
    if (!this.hasDialogTarget) return this.expand()

    this.dialogTarget.showModal()
    // Focus the editor, not the first focusable thing in the dialog, which is
    // the close button -- opening a composer and landing on "close" is the one
    // control you did not ask for.
    const editable = this.element.querySelector(".tiptap_area")
    if (editable) editable.focus()
    else if (this.hasInputTarget) this.inputTarget.focus()
  }

  close() {
    if (this.hasDialogTarget) this.dialogTarget.close()
  }

  // A native modal's backdrop is painted by the dialog itself, so a click on it
  // reports the dialog as the target. Anything inside the form reports that
  // instead, which is how the two are told apart without a separate overlay.
  backdropClose(event) {
    if (event.target === this.dialogTarget) this.dialogTarget.close()
  }

  closed() {
    this.collapsed = true
  }

  // --- inline shape (amber) ---

  expand() {
    this.collapsed = false
    if (this.hasBoxTarget) this.boxTarget.classList.add(this.expandedClassValue)
    if (this.hasFooterTarget) this.footerTarget.hidden = false
  }

  collapse(event) {
    if (this.hasInputTarget && this.inputTarget.value.trim().length > 0) return
    if (event?.relatedTarget && this.element.contains(event.relatedTarget)) return

    this.collapsed = true
    if (this.hasBoxTarget) this.boxTarget.classList.remove(this.expandedClassValue)
    if (this.hasFooterTarget) this.footerTarget.hidden = true
  }

  // Toggles a visible "attached" state on the enclosing <label> so picking a
  // file gives some feedback -- the <input> itself is visually-hidden.
  mediaSelected(event) {
    const label = event.target.closest("label")
    if (label) label.classList.toggle("compose-action--attached", event.target.files.length > 0)
  }

  syncTitle() {
    if (!this.hasTitleTarget || !this.hasInputTarget) return

    const text = this.inputTarget.value.replace(/<[^>]+>/g, " ").replace(/\s+/g, " ").trim()
    const line = text.split("\n").find((row) => row.trim().length > 0) || text
    this.titleTarget.value = line.slice(0, 300)
  }
}
