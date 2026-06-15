import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  submit(event) {
    if (!this.element.reportValidity()) {
      event.preventDefault()
      return
    }
    this.element.requestSubmit()
  }
}