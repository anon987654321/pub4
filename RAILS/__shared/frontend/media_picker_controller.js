import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "preview", "filters", "presets", "guidance"]
  static values = {
    coverLabel: { type: String, default: "Cover" },
    removeLabel: { type: String, default: "Remove" },
    moveLabel: { type: String, default: "Move photo" },
    guidanceKey: { type: String, default: "pub4-photo-guidance" }
  }

  connect() {
    this.objectUrls = []
    this.dragIndex = null
    this.#restoreGuidance()
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

  // Photo-look presets belong to a photo. Shown once there is one, hidden again
  // when the last thumbnail is removed.
  dismissGuidance(event) {
    event?.preventDefault()
    if (this.hasGuidanceTarget) this.guidanceTarget.hidden = true
    try { localStorage.setItem(this.guidanceKeyValue, "1") } catch (_) {}
  }

  #restoreGuidance() {
    if (!this.hasGuidanceTarget) return
    try {
      this.guidanceTarget.hidden = localStorage.getItem(this.guidanceKeyValue) === "1"
    } catch (_) {}
  }

  #syncPresets(hasImages) {
    if (!this.hasPresetsTarget) return

    this.presetsTarget.toggleAttribute("hidden", !hasImages)
  }

  #renderPreview(files) {
    if (!this.hasPreviewTarget) return
    if (!files?.length) {
      this.previewTarget.innerHTML = ""
      this.#syncPresets(false)
      return
    }
    this.#clearObjectUrls()
    this.previewTarget.innerHTML = ""
    this.#syncPresets(Array.from(files).some((file) => file.type.startsWith("image/")))

    Array.from(files).slice(0, 6).forEach((file, index) => {
      if (!file.type.startsWith("image/")) return

      const wrap = document.createElement("div")
      wrap.className = "media-thumb"
      wrap.draggable = true
      wrap.dataset.index = index
      wrap.addEventListener("dragstart", () => { this.dragIndex = index })
      wrap.addEventListener("dragover", (event) => event.preventDefault())
      wrap.addEventListener("drop", (event) => {
        event.preventDefault()
        this.#moveFile(this.dragIndex, index)
      })

      const img = document.createElement("img")
      img.alt = file.name
      img.className = "media-picker-thumb"

      const url = URL.createObjectURL(file)
      this.objectUrls.push(url)
      img.src = url

      const controls = document.createElement("div")
      controls.className = "media-thumb-controls"

      if (index === 0) {
        const cover = document.createElement("span")
        cover.className = "media-thumb-cover"
        cover.textContent = this.coverLabelValue
        controls.appendChild(cover)
      }

      const move = document.createElement("button")
      move.type = "button"
      move.className = "media-thumb-move"
      move.textContent = index === 0 ? "→" : "←"
      move.setAttribute("aria-label", this.moveLabelValue + ": " + file.name)
      move.addEventListener("click", () => this.#moveFile(index, index === 0 ? Math.min(index + 1, files.length - 1) : index - 1))

      const remove = document.createElement("button")
      remove.type = "button"
      remove.className = "media-thumb-rm"
      remove.textContent = "✕"
      remove.setAttribute("aria-label", this.removeLabelValue + " " + file.name)
      remove.addEventListener("click", () => this.#removeFile(index))

      controls.append(move, remove)
      wrap.append(img, controls)
      this.previewTarget.appendChild(wrap)
    })
  }

  #moveFile(from, to) {
    const files = Array.from(this.inputTarget.files || [])
    if (from == null || to == null || from === to || !files[from] || !files[to]) return
    const file = files.splice(from, 1)[0]
    files.splice(to, 0, file)

    const transfer = new DataTransfer()
    files.forEach(candidate => transfer.items.add(candidate))
    this.inputTarget.files = transfer.files
    this.#renderPreview(transfer.files)
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
