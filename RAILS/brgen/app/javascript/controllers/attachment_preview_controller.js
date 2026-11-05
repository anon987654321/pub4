import { Controller } from "@hotwired/stimulus"

// A chosen photo shows as a thumbnail above the composer with a control that
// takes it off again. The file field is visually hidden behind the camera
// icon, so before this a picked photo gave no sign until the message was sent.
// Anything that is not an image (the voice recorder fills the same field and
// reports its own state) shows nothing here.
export default class extends Controller {
  static targets = ["input", "preview"]
  static values = { alt: String, remove: String }

  disconnect() {
    this.#revoke()
  }

  show() {
    this.#revoke()
    this.previewTarget.replaceChildren()
    const file = this.inputTarget.files?.[0]
    if (!file || !file.type.startsWith("image/")) {
      this.previewTarget.hidden = true
      return
    }

    this.url = URL.createObjectURL(file)
    const image = document.createElement("img")
    image.src = this.url
    image.alt = this.altValue

    const remove = document.createElement("button")
    remove.type = "button"
    remove.className = "button button-ghost button-small"
    remove.textContent = this.removeValue
    remove.addEventListener("click", () => this.clear())
    this.previewTarget.append(image, remove)
    this.previewTarget.hidden = false
  }

  clear() {
    this.inputTarget.value = ""
    this.show()
    this.element.querySelector("textarea")?.focus()
  }

  #revoke() {
    if (this.url) URL.revokeObjectURL(this.url)
    this.url = null
  }
}
