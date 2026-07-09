import { Controller } from "@hotwired/stimulus"

const STORAGE_KEY = "brgen-dating-intro-seen"

export default class extends Controller {
  static targets = ["intro", "discover"]

  startX = 0
  startY = 0
  dragging = false

  connect() {
    if (sessionStorage.getItem(STORAGE_KEY) === "1") {
      this.#openDiscover(false)
    }
  }

  pointerdown(event) {
    this.startX = event.clientX
    this.startY = event.clientY
    this.dragging = true
    this.introTarget.setPointerCapture?.(event.pointerId)
  }

  pointermove(event) {
    if (!this.dragging) return
    const dy = event.clientY - this.startY
    const dx = event.clientX - this.startX
    const distance = Math.hypot(dx, dy)
    if (distance > 12) {
      this.introTarget.style.transform = `translate(${dx * 0.12}px, ${dy * 0.18}px)`
      this.introTarget.style.opacity = String(Math.max(0.35, 1 - distance / 280))
    }
  }

  pointerup(event) {
    if (!this.dragging) return
    this.dragging = false
    const dx = event.clientX - this.startX
    const dy = event.clientY - this.startY
    const distance = Math.hypot(dx, dy)
    if (distance > 48 || distance < 6) this.#openDiscover(true)
    else this.#resetIntro()
  }

  pointercancel() {
    this.dragging = false
    this.#resetIntro()
  }

  dismiss() {
    this.#openDiscover(true)
  }

  #openDiscover(persist) {
    this.introTarget.classList.add("dating-intro--dismissed")
    this.introTarget.style.transform = ""
    this.introTarget.style.opacity = ""
    if (persist) sessionStorage.setItem(STORAGE_KEY, "1")

    window.setTimeout(() => {
      this.introTarget.hidden = true
      this.discoverTarget.hidden = false
      this.discoverTarget.removeAttribute("aria-hidden")
    }, 380)
  }

  #resetIntro() {
    this.introTarget.style.transition = "opacity 220ms ease, transform 220ms ease"
    this.introTarget.style.transform = ""
    this.introTarget.style.opacity = ""
    window.setTimeout(() => {
      this.introTarget.style.transition = ""
    }, 220)
  }
}