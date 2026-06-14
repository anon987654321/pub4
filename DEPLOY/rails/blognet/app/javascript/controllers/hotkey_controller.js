// Hotkey controller — vim-style j/k navigation, ? help, n new post etc.
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["item"]

  connect() {
    this.boundHandle = this.handleKey.bind(this)
    document.addEventListener("keydown", this.boundHandle, { passive: true })
    this.index = 0
    this.prefersReduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches
  }

  disconnect() {
    document.removeEventListener("keydown", this.boundHandle)
  }

  handleKey(e) {
    if (["INPUT", "TEXTAREA", "SELECT"].includes(document.activeElement.tagName)) return
    if (e.key === "j" || e.key === "ArrowDown") {
      e.preventDefault()
      this.move(1)
    } else if (e.key === "k" || e.key === "ArrowUp") {
      e.preventDefault()
      this.move(-1)
    } else if (e.key === "?") {
      e.preventDefault()
      this.showHelp()
    } else if (e.key.toLowerCase() === "n") {
      const newLink = document.querySelector('a[href*="/new"], [data-hotkey-new]')
      if (newLink) newLink.click()
    } else if (e.key === "Escape") {
      document.querySelectorAll(".hotkey-focus").forEach(el => el.classList.remove("hotkey-focus"))
    }
  }

  move(delta) {
    const items = this.hasItemTarget ? this.itemTargets : document.querySelectorAll(".post, .listing, .swipe-card, article, .card")
    if (!items.length) return
    this.index = Math.max(0, Math.min(items.length - 1, this.index + delta))
    const el = items[this.index]
    const behavior = this.prefersReduced ? "auto" : "smooth"
    el.scrollIntoView({ behavior, block: "center" })
    document.querySelectorAll(".hotkey-focus").forEach(n => n.classList.remove("hotkey-focus"))
    el.classList.add("hotkey-focus")
    setTimeout(() => el.classList.remove("hotkey-focus"), 900)
    const btn = el.querySelector("button, a, [tabindex]")
    if (btn) btn.focus({ preventScroll: true })
  }

  showHelp() {
    const existing = document.querySelector(".hotkey-help")
    if (existing) existing.remove()
    const help = document.createElement("div")
    help.className = "hotkey-help"
    help.setAttribute("role", "status")
    help.innerHTML = `
      <div style="position:fixed;bottom:16px;left:50%;transform:translateX(-50%);background:var(--surface);border:1px solid var(--border);padding:6px 12px;font-size:10px;border-radius:3px;z-index:9999;box-shadow:0 2px 8px rgba(0,0,0,0.3)">
        j/k ↓↑: nav &nbsp; n: new &nbsp; esc: clear &nbsp; ?: close
      </div>
    `
    document.body.appendChild(help)
    setTimeout(() => { if (help && help.parentNode) help.parentNode.removeChild(help) }, 1400)
  }
}
