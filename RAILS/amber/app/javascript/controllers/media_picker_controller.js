import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "preview"]

  trigger() {
    this.inputTarget.click()
  }

  pick() {
    this.#renderPreview(this.inputTarget.files)
  }

  dragover(event) {
    event.preventDefault()
    this.element.classList.add("is-dragging")
  }

  dragleave() {
    this.element.classList.remove("is-dragging")
  }

  drop(event) {
    event.preventDefault()
    this.element.classList.remove("is-dragging")
    this.inputTarget.files = event.dataTransfer.files
    this.#renderPreview(event.dataTransfer.files)
  }

  #renderPreview(files) {
    if (!this.hasPreviewTarget) return
    this.previewTarget.innerHTML = ""
    Array.from(files).slice(0, 6).forEach((file) => {
      if (!file.type.startsWith("image/")) return
      const img = document.createElement("img")
      img.alt = file.name
      img.src = URL.createObjectURL(file)
      img.className = "media-picker-thumb"
      this.previewTarget.appendChild(img)
    })
  }
}
