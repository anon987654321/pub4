import { Controller } from "@hotwired/stimulus"

// Two shapes share this controller.
//
// brgen opens the composer as a <dialog>: the resting row is a thin trigger and
// the writing surface floats over the feed, so the feed does not reflow when you
// start writing. amber still expands in place, so expand/collapse stay.
export default class extends Controller {
  static targets = ["input", "title", "footer", "box", "dialog", "media"]
  static values = {
    expandedClass: { type: String, default: "compose-box--expanded" },
    // The question asked before a dialog holding text or media closes.
    discard: { type: String, default: "" },
    // The media list's words, translated by the view: "Fjern %{name}" and the
    // thumbnail's alt text.
    removeMedia: { type: String, default: "" },
    mediaAlt: { type: String, default: "" }
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
    this.revokeMedia()
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
    if (this.hasDialogTarget && this.mayClose()) this.dialogTarget.close()
  }

  // A native modal's backdrop is painted by the dialog itself, so a click on it
  // reports the dialog as the target. Anything inside the form reports that
  // instead, which is how the two are told apart without a separate overlay.
  backdropClose(event) {
    if (event.target === this.dialogTarget && this.mayClose()) this.dialogTarget.close()
  }

  // Esc fires cancel before the dialog closes; declining keeps it open.
  cancel(event) {
    if (!this.mayClose()) event.preventDefault()
  }

  // A stray tap on the backdrop or Esc should not cost a written post. The
  // text survives in the draft store, but an attached photo or recording does
  // not, so the writer is asked first.
  mayClose() {
    if (!this.holdsWork() || !this.discardValue) return true

    return window.confirm(this.discardValue)
  }

  holdsWork() {
    const text = this.hasInputTarget ? this.inputTarget.value.replace(/<[^>]+>/g, "").trim() : ""
    const files = Array.from(this.element.querySelectorAll("input[type=file]")).some((input) => input.files?.length > 0)
    return text.length > 0 || files
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
    this.renderMedia()
  }

  // What is attached, in the media list (brgen): a thumbnail for a photo, the
  // file name for a recording, and a control that takes each off again. The
  // icon's attached state was the only sign, and it could not be undone short
  // of closing the composer.
  renderMedia() {
    if (!this.hasMediaTarget) return

    this.revokeMedia()
    const chosen = Array.from(this.element.querySelectorAll("input[type=file]")).filter((input) => input.files?.length)
    const items = chosen.map((input) => this.mediaItem(input))
    this.mediaTarget.replaceChildren(...items)
    this.mediaTarget.hidden = items.length === 0
  }

  mediaItem(input) {
    const [file] = input.files
    const item = document.createElement("li")

    if (file.type.startsWith("image/")) {
      const image = document.createElement("img")
      image.src = this.mediaUrl(file)
      image.alt = this.mediaAltValue
      item.append(image)
    } else {
      const name = document.createElement("span")
      name.textContent = file.name
      item.append(name)
    }

    const remove = document.createElement("button")
    remove.type = "button"
    remove.className = "button button-ghost button-small"
    remove.textContent = this.removeMediaValue.replace("%{name}", file.name)
    remove.addEventListener("click", () => this.removeMedia(input))
    item.append(remove)
    return item
  }

  removeMedia(input) {
    input.value = ""
    input.dispatchEvent(new Event("change", { bubbles: true }))
    const editable = this.element.querySelector(".tiptap_area")
    if (editable) editable.focus()
    else if (this.hasInputTarget) this.inputTarget.focus()
  }

  mediaUrl(file) {
    const url = URL.createObjectURL(file)
    this.mediaUrls = [ ...(this.mediaUrls || []), url ]
    return url
  }

  revokeMedia() {
    (this.mediaUrls || []).forEach((url) => URL.revokeObjectURL(url))
    this.mediaUrls = []
  }

  syncTitle() {
    if (!this.hasTitleTarget || !this.hasInputTarget) return

    const text = this.inputTarget.value.replace(/<[^>]+>/g, " ").replace(/\s+/g, " ").trim()
    const line = text.split("\n").find((row) => row.trim().length > 0) || text
    this.titleTarget.value = line.slice(0, 300)
  }
}
