import { Controller } from "@hotwired/stimulus"

// The copied notice comes from the view (data-share-copied-value, rendered with
// t()), and only the label target changes, so the icon beside it stays.
export default class extends Controller {
  static targets = ["label"]
  static values = { title: String, url: String, copied: String }

  async share() {
    const payload = { title: this.titleValue, url: this.urlValue || location.href }
    if (navigator.share) {
      await navigator.share(payload).catch(() => {})
      return
    }

    await navigator.clipboard.writeText(payload.url)
    if (!this.hasLabelTarget || !this.copiedValue) return

    const label = this.labelTarget.textContent
    this.labelTarget.textContent = this.copiedValue
    setTimeout(() => { this.labelTarget.textContent = label }, 1800)
  }
}
