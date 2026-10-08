import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.rows = new Map()
    this.onInitialize = this.initializeUpload.bind(this)
    this.onProgress = this.updateProgress.bind(this)
    this.onError = this.showError.bind(this)
    this.onEnd = this.finishUpload.bind(this)

    this.element.addEventListener("direct-upload:initialize", this.onInitialize)
    this.element.addEventListener("direct-upload:progress", this.onProgress)
    this.element.addEventListener("direct-upload:error", this.onError)
    this.element.addEventListener("direct-upload:end", this.onEnd)
  }

  disconnect() {
    this.element.removeEventListener("direct-upload:initialize", this.onInitialize)
    this.element.removeEventListener("direct-upload:progress", this.onProgress)
    this.element.removeEventListener("direct-upload:error", this.onError)
    this.element.removeEventListener("direct-upload:end", this.onEnd)
  }

  initializeUpload({ detail: { id, file } }) {
    const row = document.createElement("div")
    row.className = "direct-upload"
    row.id = `direct-upload-${id}`
    row.setAttribute("role", "status")
    row.setAttribute("aria-live", "polite")

    const name = document.createElement("span")
    name.className = "direct-upload-name"
    name.textContent = file.name

    const progress = document.createElement("progress")
    progress.className = "direct-upload-progress"
    progress.max = 100
    progress.value = 0
    progress.setAttribute("aria-label", `Uploading ${file.name}`)

    const value = document.createElement("span")
    value.className = "direct-upload-value"
    value.textContent = "0%"

    row.append(name, progress, value)
    this.element.insertAdjacentElement("afterend", row)
    this.rows.set(id, { row, progress, value })
  }

  updateProgress({ detail: { id, progress } }) {
    const upload = this.rows.get(id)
    if (!upload) return

    const percent = Math.round(progress)
    upload.progress.value = percent
    upload.value.textContent = `${percent}%`
  }

  showError(event) {
    event.preventDefault()
    const { id, error } = event.detail
    const upload = this.rows.get(id)
    if (!upload) return

    upload.row.classList.add("direct-upload-error")
    upload.row.setAttribute("role", "alert")
    upload.value.textContent = error || "Upload failed"
  }

  finishUpload({ detail: { id } }) {
    const upload = this.rows.get(id)
    if (!upload || upload.row.classList.contains("direct-upload-error")) return

    upload.progress.value = 100
    upload.value.textContent = "Uploaded"
    upload.row.classList.add("direct-upload-complete")
  }
}
