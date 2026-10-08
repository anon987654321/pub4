import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["form", "input", "status"]
  static values = {
    delay: { type: Number, default: 300 },
    updating: { type: String, default: "Updating results…" },
    updated: { type: String, default: "Results updated" },
    failed: { type: String, default: "Search could not be completed" }
  }

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

  // A control can belong to this form from elsewhere on the page through its
  // form attribute: the storefront's filter drawer sits in the page while the
  // field it narrows sits in the header. Its change never passes through the
  // form element, so the document relays it. A control inside the form is
  // left to input() and to the form's own submit.
  relay(event) {
    const control = event.target
    if (!this.hasFormTarget || control.form !== this.formTarget || this.formTarget.contains(control)) return

    this.submitForm()
  }

  submitForm() {
    if (!this.hasFormTarget) return

    const action = new URL(this.formTarget.action, window.location.origin)
    action.searchParams.set("format", "turbo_stream")
    this.formTarget.action = action.pathname + action.search
    this.formTarget.setAttribute("aria-busy", "true")
    if (this.hasStatusTarget) this.statusTarget.textContent = this.updatingValue
    this.formTarget.requestSubmit()
  }

  complete(event) {
    if (event.target !== this.formTarget) return

    this.formTarget.removeAttribute("aria-busy")
    if (this.hasStatusTarget) {
      this.statusTarget.textContent = event.detail.success ? this.updatedValue : this.failedValue
    }
    // vYroQxg .search.active when live results are on screen
    const shell = this.element.classList.contains("search") ? this.element : this.element.closest(".search")
    if (shell) {
      const q = this.hasInputTarget ? this.inputTarget.value.trim() : ""
      shell.classList.toggle("active", q.length > 0 && event.detail?.success !== false)
    }
  }
}
