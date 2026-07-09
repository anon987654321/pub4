import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["template", "container"]

  add(event) {
    event.preventDefault()
    const content = this.templateTarget.innerHTML.replace(/NEW_RECORD/g, new Date().getTime().toString())
    this.containerTarget.insertAdjacentHTML("beforeend", content)
  }

  remove(event) {
    event.preventDefault()
    const wrapper = event.currentTarget.closest("[data-new-record]")
    if (!wrapper) return

    const destroyInput = wrapper.querySelector("input[name*='[_destroy]']")
    const persisted = wrapper.dataset.newRecord === "false"
    if (persisted && destroyInput) {
      destroyInput.value = "1"
      wrapper.hidden = true
    } else {
      wrapper.remove()
    }
  }
}
