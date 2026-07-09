import { Controller } from "@hotwired/stimulus"
import flatpickr from "flatpickr"

export default class extends Controller {
  connect() {
    this.pickers = Array.from(this.element.querySelectorAll("input[type='date'], input[type='datetime-local']"))
      .map(input => flatpickr(input, {
        allowInput: true,
        enableTime: input.type === "datetime-local",
        dateFormat: input.type === "datetime-local" ? "Y-m-d\\TH:i" : "Y-m-d",
        altInput: true,
        altFormat: input.type === "datetime-local" ? "M j, Y H:i" : "M j, Y"
      }))
  }

  disconnect() {
    this.pickers?.forEach(picker => picker?.destroy?.())
  }
}
