import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["tab", "panel"]

  connect() {
    if (window.location.hash) this.show(window.location.hash.slice(1))
  }

  select(event) {
    this.show(event.currentTarget.dataset.tabId)
  }

  show(id) {
    this.tabTargets.forEach(tab => {
      const active = tab.dataset.tabId === id
      tab.setAttribute("aria-selected", active)
      tab.tabIndex = active ? 0 : -1
    })
    this.panelTargets.forEach(panel => {
      panel.hidden = panel.id !== id
      panel.setAttribute("role", "tabpanel")
    })
    history.replaceState(null, "", `#${id}`)
  }
}