import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "preview"]

  connect() {
    this.objectUrls = []
  }

  disconnect() {
    this.#clearObjectUrls()
  }

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
    const accepted = Array.from(event.dataTransfer.files).filter((file) => file.type.startsWith("image/"))
    const transfer = new DataTransfer()
    accepted.forEach((file) => transfer.items.add(file))
    this.inputTarget.files = transfer.files
    this.#renderPreview(transfer.files)
  }

  #renderPreview(files) {
    if (!this.hasPreviewTarget) return
    this.#clearObjectUrls()
    this.previewTarget.innerHTML = ""
    Array.from(files).slice(0, 6).forEach((file) => {
      if (!file.type.startsWith("image/")) return
      const img = document.createElement("img")
      img.alt = file.name
      const url = URL.createObjectURL(file)
      this.objectUrls.push(url)
      img.src = url
      img.className = "media-picker-thumb"
      this.previewTarget.appendChild(img)
    })
  }

  #clearObjectUrls() {
    this.objectUrls.forEach((url) => URL.revokeObjectURL(url))
    this.objectUrls = []
  }
}
