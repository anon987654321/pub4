import { Controller } from "@hotwired/stimulus"

// The wardrobe's category select submits its GET form on change; the server
// filters, so infinite scroll appends pages of the same category. It used to
// hide the cards already loaded and leave every appended page unfiltered.
export default class extends Controller {
  submit() {
    this.element.requestSubmit()
  }
}
