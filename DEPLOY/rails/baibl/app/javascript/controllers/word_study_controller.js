import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { verseId: Number, position: Number, url: String }

  toggle(e) {
    e.stopPropagation()
    const popover = document.getElementById("word-popover")
    const active  = document.querySelector(".word.active")

    if (active === this.element) {
      this.close(popover)
      return
    }
    if (active) active.classList.remove("active")
    this.element.classList.add("active")
    this.load(popover)
    this.position(popover)
  }

  async load(popover) {
    popover.removeAttribute("hidden")
    popover.innerHTML = "<span class='ws-loading'>…</span>"
    const r = await fetch(this.urlValue, { headers: { Accept: "text/html" } })
    popover.innerHTML = await r.text()
  }

  position(popover) {
    const rect = this.element.getBoundingClientRect()
    const top  = rect.bottom + window.scrollY + 6
    const left = Math.min(rect.left + window.scrollX, window.innerWidth - 320)
    popover.style.top  = `${top}px`
    popover.style.left = `${Math.max(8, left)}px`
  }

  close(popover) {
    this.element.classList.remove("active")
    popover.setAttribute("hidden", "")
    popover.innerHTML = ""
  }

  disconnect() {
    const popover = document.getElementById("word-popover")
    if (popover) { popover.setAttribute("hidden", ""); popover.innerHTML = "" }
  }
}
