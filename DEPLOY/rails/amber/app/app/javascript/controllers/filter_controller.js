import { Controller } from "@hotwired/stimulus"
export default class extends Controller {
  static targets = ["select", "grid"]
  filter() {
    const val = this.selectTarget.value
    this.gridTarget.querySelectorAll("[data-category]").forEach(c => {
      c.hidden = val && c.dataset.category !== val
    })
  }
}
