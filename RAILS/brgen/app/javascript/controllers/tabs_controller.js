import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["tab", "panel"]

  connect() {
    this.onKeydown = this.handleKeydown.bind(this)
    this.element.addEventListener("keydown", this.onKeydown)
    this.syncFromLocation()
  }

  disconnect() {
    this.element.removeEventListener("keydown", this.onKeydown)
  }

  select(event) {
    const tab = event.currentTarget
    if (!tab) return
    this.activate(tab)
  }

  handleKeydown(event) {
    if (!["ArrowLeft", "ArrowRight", "Home", "End"].includes(event.key)) return
    const tabs = this.tabTargets
    if (!tabs.length) return

    event.preventDefault()
    const index = tabs.indexOf(document.activeElement)
    const nextIndex = event.key === "Home" ? 0 : event.key === "End" ? tabs.length - 1 : (index + (event.key === "ArrowRight" ? 1 : -1) + tabs.length) % tabs.length
    tabs[nextIndex].focus()
    this.activate(tabs[nextIndex], true)
  }

  activate(tab, fromKeyboard = false) {
    const hash = tab.dataset.tabsHashValue
    this.tabTargets.forEach(candidate => {
      const active = candidate === tab
      candidate.setAttribute("aria-selected", active ? "true" : "false")
      candidate.classList.toggle("active", active)
      candidate.tabIndex = active ? 0 : -1
    })

    this.panelTargets.forEach(panel => {
      const panelHash = panel.dataset.tabsHashValue
      const active = !panelHash || panelHash === hash
      panel.hidden = !active
      panel.setAttribute("aria-labelledby", tab.id || "")
    })

    if (!fromKeyboard) {
      if (hash) history.replaceState(null, "", hash)
    }
  }

  syncFromLocation() {
    const hash = window.location.hash || this.tabTargets.find(tab => tab.getAttribute("aria-selected") === "true")?.dataset.tabsHashValue
    const tab = this.tabTargets.find(candidate => candidate.dataset.tabsHashValue === hash) || this.tabTargets[0]
    if (tab) this.activate(tab, true)
  }
}
