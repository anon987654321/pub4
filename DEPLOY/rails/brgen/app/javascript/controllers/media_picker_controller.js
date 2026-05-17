import { Controller } from "@hotwired/stimulus"

const FILTERS = [
  { name: "Original", css: "none" },
  { name: "Vivid",    css: "saturate(180%) contrast(110%)" },
  { name: "Warm",     css: "sepia(30%) saturate(140%) brightness(105%)" },
  { name: "Cool",     css: "hue-rotate(20deg) saturate(110%) brightness(95%)" },
  { name: "Fade",     css: "contrast(82%) brightness(112%) saturate(68%)" },
  { name: "Noir",     css: "grayscale(100%) contrast(150%)" },
  { name: "Sepia",    css: "sepia(80%)" },
  { name: "Chrome",   css: "contrast(118%) brightness(104%) saturate(135%)" },
]

export default class extends Controller {
  static targets = ["input", "preview", "filters"]
  static values  = { multiple: Boolean }

  #files  = []
  #active = 0  // FILTERS index

  trigger() { this.inputTarget.click() }

  pick(e) {
    this.#files = Array.from(e.target.files)
    if (!this.#files.length) return
    this.#active = 0
    this.#renderPreviews()
    this.#renderFilters()
  }

  // ── private ──────────────────────────────────────────────

  #renderPreviews() {
    this.previewTarget.innerHTML = ""
    this.#files.forEach((f, i) => {
      const reader = new FileReader()
      reader.onload = ev => {
        const wrap = document.createElement("div")
        wrap.className = "media-thumb"
        wrap.dataset.index = i
        const img = document.createElement("img")
        img.src = ev.target.result
        img.style.filter = FILTERS[this.#active].css
        img.dataset.src = ev.target.result
        const rm = document.createElement("button")
        rm.type = "button"
        rm.className = "media-thumb-rm"
        rm.textContent = "✕"
        rm.addEventListener("click", () => {
          this.#files.splice(i, 1)
          wrap.remove()
          if (!this.#files.length) {
            this.inputTarget.value = ""
            this.filtersTarget.innerHTML = ""
          }
        })
        wrap.append(img, rm)
        this.previewTarget.appendChild(wrap)
      }
      reader.readAsDataURL(f)
    })
  }

  #renderFilters() {
    if (!this.hasFiltersTarget) return
    const strip = this.filtersTarget
    strip.innerHTML = ""
    const firstReader = new FileReader()
    firstReader.onload = ev => {
      FILTERS.forEach((filter, idx) => {
        const btn   = document.createElement("button")
        btn.type    = "button"
        btn.className = "filter-btn" + (idx === this.#active ? " active" : "")
        btn.dataset.index = idx

        const canvas = document.createElement("canvas")
        canvas.width  = 72
        canvas.height = 72

        const img  = new Image()
        img.onload = () => {
          const ctx = canvas.getContext("2d")
          ctx.filter = filter.css
          // Cover crop
          const scale = Math.max(72 / img.width, 72 / img.height)
          const w = img.width * scale, h = img.height * scale
          ctx.drawImage(img, (72 - w) / 2, (72 - h) / 2, w, h)
        }
        img.src = ev.target.result

        const label = document.createElement("span")
        label.className = "filter-label"
        label.textContent = filter.name

        btn.append(canvas, label)
        btn.addEventListener("click", () => this.#applyFilter(idx))
        strip.appendChild(btn)
      })
    }
    firstReader.readAsDataURL(this.#files[0])
  }

  async #applyFilter(idx) {
    this.#active = idx
    // Update active state on strip
    this.filtersTarget.querySelectorAll(".filter-btn").forEach((b, i) =>
      b.classList.toggle("active", i === idx)
    )
    // Update live preview CSS filter (instant, no re-encode yet)
    this.previewTarget.querySelectorAll("img").forEach(img => {
      img.style.filter = FILTERS[idx].css
    })
    // Re-encode all files with the chosen filter and replace input
    const blobs = await Promise.all(this.#files.map(f => this.#encodeWithFilter(f, FILTERS[idx].css)))
    const dt = new DataTransfer()
    blobs.forEach((blob, i) => dt.items.add(new File([blob], this.#files[i].name, { type: "image/jpeg" })))
    this.inputTarget.files = dt.files
  }

  #encodeWithFilter(file, filterCss) {
    return new Promise(resolve => {
      const reader = new FileReader()
      reader.onload = ev => {
        const img = new Image()
        img.onload = () => {
          const canvas = document.createElement("canvas")
          canvas.width  = img.width
          canvas.height = img.height
          const ctx = canvas.getContext("2d")
          ctx.filter = filterCss
          ctx.drawImage(img, 0, 0)
          canvas.toBlob(resolve, "image/jpeg", 0.92)
        }
        img.src = ev.target.result
      }
      reader.readAsDataURL(file)
    })
  }
}
