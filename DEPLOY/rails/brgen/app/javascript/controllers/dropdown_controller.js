import Dropdown from "@stimulus-components/dropdown"

export default class extends Dropdown {
  connect() {
    super.connect()
    this.syncExpanded(false)
  }

  toggle(event) {
    super.toggle(event)
    this.syncExpanded(!this.menuTarget.classList.contains("hidden"))
  }

  hide(event) {
    super.hide(event)
    this.syncExpanded(false)
  }

  syncExpanded(open) {
    const button = this.element.querySelector("[data-dropdown-button]")
    if (button) button.setAttribute("aria-expanded", open ? "true" : "false")
  }
}
