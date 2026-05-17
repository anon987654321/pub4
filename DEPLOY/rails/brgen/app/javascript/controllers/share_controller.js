import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { title: String, url: String }

  async share() {
    const payload = { title: this.titleValue, url: this.urlValue || location.href }
    if (navigator.share) {
      await navigator.share(payload).catch(() => {})
    } else {
      await navigator.clipboard.writeText(payload.url)
      this.element.textContent = "Copied"
      setTimeout(() => { this.element.textContent = "Share" }, 1800)
    }
  }
}
