import { Controller } from "@hotwired/stimulus"
import { enqueueSync } from "pwa/offline_store"

export default class extends Controller {
  static targets = ["card", "stack"]
  static values = { likeUrl: String, passUrl: String }

  startX = 0
  startY = 0
  current = null

  connect() {
    this.current = this.cardTargets[0]
    if (!this.current) return
    this.current.dataset.datingSwipeActive = "true"
  }

  pointerdown(event) {
    if (!this.current) return
    this.startX = event.clientX
    this.startY = event.clientY
    this.current.setPointerCapture?.(event.pointerId)
  }

  pointermove(event) {
    if (!this.current) return
    const dx = event.clientX - this.startX
    const dy = event.clientY - this.startY
    const rotate = dx * 0.08
    this.current.style.transform = `translate(${dx}px, ${dy}px) rotate(${rotate}deg)`
  }

  async pointerup(event) {
    if (!this.current) return
    const dx = event.clientX - this.startX
    if (dx > 80) await this.#act("like")
    else if (dx < -80) await this.#act("pass")
    else this.#resetCard()
  }

  like() { this.#act("like") }
  pass() { this.#act("pass") }

  async #act(direction) {
    const card = this.current
    const url = direction === "like" ? this.likeUrlValue : this.passUrlValue
    const userId = card?.dataset.userId
    if (!card || !url || !userId) return

    card.style.transition = "transform 220ms ease"
    card.style.transform = direction === "like" ? "translate(120%, -10%) rotate(18deg)" : "translate(-120%, -10%) rotate(-18deg)"

    try {
      await fetch(url, {
        method: "POST",
        headers: {
          "X-CSRF-Token": document.querySelector("meta[name=csrf-token]")?.content || "",
          "Accept": "text/vnd.turbo-stream.html, text/html"
        },
        body: new URLSearchParams({ user_id: userId })
      })
    } catch (_) {
      await enqueueSync({ url, method: "POST", body: { user_id: userId } })
    }

    setTimeout(() => {
      card.remove()
      this.current = this.cardTargets[0]
      if (this.current) {
        this.#resetCard()
        this.current.dataset.datingSwipeActive = "true"
      }
    }, 220)
  }

  #resetCard() {
    if (!this.current) return
    this.current.style.transition = ""
    this.current.style.transform = ""
  }
}