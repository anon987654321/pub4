import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["form", "input", "status"]
  static values = { delay: { type: Number, default: 300 } }

  connect() {
    this.timeout = null
  }

  disconnect() {
    clearTimeout(this.timeout)
  }

  input() {
    clearTimeout(this.timeout)
    this.timeout = setTimeout(() => this.submitForm(), this.delayValue)
  }

  submitForm() {
    if (!this.hasFormTarget) return

    const action = new URL(this.formTarget.action, window.location.origin)
    action.searchParams.set("format", "turbo_stream")
    this.formTarget.action = action.pathname + action.search
    this.formTarget.setAttribute("aria-busy", "true")
    if (this.hasStatusTarget) this.statusTarget.textContent = "Updating results"
    this.formTarget.requestSubmit()
  }

  complete(event) {
    if (event.target !== this.formTarget) return

    this.formTarget.removeAttribute("aria-busy")
    if (this.hasStatusTarget) {
      this.statusTarget.textContent = event.detail.success ? "Results updated" : "Search could not be completed"
    }
    // vYroQxg .search.active when live results are on screen
    const shell = this.element.classList.contains("search") ? this.element : this.element.closest(".search")
    if (shell) {
      const q = this.hasInputTarget ? this.inputTarget.value.trim() : ""
      shell.classList.toggle("active", q.length > 0 && event.detail?.success !== false)
    }
  }
}
