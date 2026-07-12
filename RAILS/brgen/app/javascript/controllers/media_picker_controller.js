import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "preview", "filters"]

  trigger() { this.inputTarget.click() }

  pick(e) {
    const files = Array.from(e.target.files).filter((file) => file.type.startsWith("image/"))
    if (!files.length) return
    this.previewTarget.innerHTML = ""
    files.forEach((f, i) => {
      const reader = new FileReader()
      reader.onload = ev => {
        const wrap = document.createElement("div")
        wrap.className = "media-thumb"
        const img = document.createElement("img")
        img.src = ev.target.result
        img.alt = f.name
        const rm = document.createElement("button")
        rm.type = "button"
        rm.className = "media-thumb-rm"
        rm.textContent = "✕"
        rm.setAttribute("aria-label", `Remove ${f.name}`)
        rm.addEventListener("click", () => {
          this.#removeFile(i)
        })
        wrap.append(img, rm)
        this.previewTarget.appendChild(wrap)
      }
      reader.readAsDataURL(f)
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
}
