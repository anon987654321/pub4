import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["button", "input"]
  static values = { theme: { type: String, default: "classic" } }

  connect() {
    this.buttonTarget.type ||= "button"
    this.buttonTarget.setAttribute(
      "aria-label",
      this.buttonTarget.getAttribute("aria-label") || "Choose color",
    )
    this.inputTarget.type = "color"
    this.sync()
    this.picker = {
      element: this.buttonTarget,
      show: () => this.open(),
      hide: () => {},
      setColor: (value) => { this.inputTarget.value = value; this.sync() },
      destroy: () => {},
    }
    this.buttonTarget.addEventListener("click", this.open)
    this.inputTarget.addEventListener("input", this.sync)
  }

  disconnect() {
    this.buttonTarget.removeEventListener("click", this.open)
    this.inputTarget.removeEventListener("input", this.sync)
    this.picker?.destroy()
    this.picker = null
  }

  open = () => this.inputTarget.click()
  sync = () => { this.buttonTarget.style.backgroundColor = this.inputTarget.value || "transparent" }

  get componentOptions() {
    return { preview: true, hue: true, interaction: { input: true, clear: true, save: true } }
  }

  get swatches() {
    return ["#A0AEC0", "#F56565", "#ED8936", "#ECC94B", "#48BB78", "#38B2AC", "#4299E1", "#667EEA", "#9F7AEA", "#ED64A6"]
  }
}
