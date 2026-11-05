import { Controller } from "@hotwired/stimulus"

// The order page's "print receipt" button. It ships hidden and shows itself
// once this controller runs, so a page without scripts offers no dead button.
export default class extends Controller {
  connect() {
    this.element.hidden = false
  }

  print() {
    window.print()
  }
}
