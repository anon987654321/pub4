import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "preview", "trigger"]
  static values  = { multiple: Boolean }

  trigger() { this.inputTarget.click() }

  pick(e) {
    const files = Array.from(e.target.files)
    if (!files.length) return
    this.previewTarget.innerHTML = ""
    files.forEach(f => {
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
        rm.addEventListener("click", () => {
          wrap.remove()
          if (!this.previewTarget.children.length) this.inputTarget.value = ""
        })
        wrap.append(img, rm)
        this.previewTarget.appendChild(wrap)
      }
      reader.readAsDataURL(f)
    })
  }
}
