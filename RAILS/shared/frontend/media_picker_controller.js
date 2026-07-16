import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "preview", "filters"]

  connect() {
    this.objectUrls = []
  }

  disconnect() {
    this.#clearObjectUrls()
  }

  trigger() {
    this.inputTarget.click()
  }

  pick(event) {
    const files = event?.target?.files || this.inputTarget.files
    this.#renderPreview(files)
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
    if (!this.hasPreviewTarget || !files?.length) return
    this.#clearObjectUrls()
    this.previewTarget.innerHTML = ""

    Array.from(files).slice(0, 6).forEach((file, index) => {
      if (!file.type.startsWith("image/")) return

      const wrap = document.createElement("div")
      wrap.className = "media-thumb"

      const img = document.createElement("img")
      img.alt = file.name
      img.className = "media-picker-thumb"

      const url = URL.createObjectURL(file)
      this.objectUrls.push(url)
      img.src = url

      const remove = document.createElement("button")
      remove.type = "button"
      remove.className = "media-thumb-rm"
      remove.textContent = "✕"
      remove.setAttribute("aria-label", `Remove ${file.name}`)
      remove.addEventListener("click", () => this.#removeFile(index))

      wrap.append(img, remove)
      this.previewTarget.appendChild(wrap)
    })
  }

  #removeFile(index) {
    const transfer = new DataTransfer()
    Array.from(this.inputTarget.files).forEach((file, fileIndex) => {
      if (fileIndex !== index) transfer.items.add(file)
    })
    this.inputTarget.files = transfer.files
    this.inputTarget.dispatchEvent(new Event("change", { bubbles: true }))
  }

  #clearObjectUrls() {
    this.objectUrls.forEach((url) => URL.revokeObjectURL(url))
    this.objectUrls = []
  }
}