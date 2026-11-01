import { Controller } from "@hotwired/stimulus"

// Mock Vipps approval (§8): brief loading shimmer, then submit the approve
// form so the flow feels like the real app's fingerprint confirmation.
export default class extends Controller {
  approve(event) {
    const button = event.currentTarget
    if (this.element.dataset.approving) return
    this.element.dataset.approving = "true"
    button.classList.add("is-loading")
    button.disabled = true
    setTimeout(() => this.element.requestSubmit(), 400)
  }
}
