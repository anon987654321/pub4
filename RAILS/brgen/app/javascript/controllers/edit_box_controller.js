import { Controller } from "@hotwired/stimulus"

// The messenger's edit box: the cursor lands at the end of the text being
// edited, where a correction usually goes, rather than before its first
// letter, and Escape cancels the way the Cancel link does.
export default class extends Controller {
  static targets = ["field", "cancel"]

  connect() {
    const field = this.fieldTarget
    field.focus()
    const end = field.value.length
    field.setSelectionRange(end, end)
  }

  cancel(event) {
    event.preventDefault()
    this.cancelTarget.click()
  }
}
