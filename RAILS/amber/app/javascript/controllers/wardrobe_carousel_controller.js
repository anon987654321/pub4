import { Controller } from "@hotwired/stimulus"

// Mix & Match Magic.
//
// Four zone carousels advance on their own, adjacent zones in opposite
// directions — head and bottom forward, top and shoes backward — so the
// combination on the mannequin keeps changing without the same two garments
// staying paired. Order within a zone comes from TasteRanker server-side, so
// index 0 is always the garment this wardrobe reaches for most.
//
// Autoplay stops for prefers-reduced-motion, while the tab is hidden, and
// while the pointer or keyboard focus is inside the dressing room — a rotation
// that moves under the cursor mid-click picks the wrong garment.
const ZONES = ["head", "top", "bottom", "shoes"]
const DIRECTION = { head: 1, top: -1, bottom: 1, shoes: -1 }

export default class extends Controller {
  static values = { zones: Object, interval: { type: Number, default: 4200 } }
  static targets = ["pick", "playToggle"]

  connect() {
    this.idx = { head: 0, top: 0, bottom: 0, shoes: 0 }
    this.timers = new Map()
    this.paused = false
    this.reducedMotion = window.matchMedia?.("(prefers-reduced-motion: reduce)")?.matches ?? false

    ZONES.forEach(zone => this.render(zone))

    this.onVisibility = () => (document.hidden ? this.stop() : this.start())
    document.addEventListener("visibilitychange", this.onVisibility)
    this.element.addEventListener("pointerenter", this.stop)
    this.element.addEventListener("pointerleave", this.start)
    this.element.addEventListener("focusin", this.stop)
    this.element.addEventListener("focusout", this.start)

    if (this.reducedMotion) this.markToggle(false)
    else this.start()
  }

  disconnect() {
    this.stop()
    document.removeEventListener("visibilitychange", this.onVisibility)
    this.element.removeEventListener("pointerenter", this.stop)
    this.element.removeEventListener("pointerleave", this.start)
    this.element.removeEventListener("focusin", this.stop)
    this.element.removeEventListener("focusout", this.start)
  }

  // Arrow functions: these are used directly as listeners above.
  start = () => {
    if (this.paused || this.reducedMotion || document.hidden) return
    ZONES.forEach((zone, i) => {
      if (this.timers.has(zone)) return
      if ((this.zonesValue[zone] || []).length < 2) return
      // Stagger each zone by a quarter interval so all four never flip on the
      // same frame — the point is a shifting combination, not a slideshow.
      const offset = (this.intervalValue / ZONES.length) * i
      const handle = window.setTimeout(() => {
        const id = window.setInterval(() => this.step(zone, DIRECTION[zone]), this.intervalValue)
        this.timers.set(zone, { kind: "interval", id })
        this.step(zone, DIRECTION[zone])
      }, offset)
      this.timers.set(zone, { kind: "timeout", id: handle })
    })
    this.markToggle(true)
  }

  stop = () => {
    this.timers.forEach(({ kind, id }) => {
      if (kind === "interval") window.clearInterval(id)
      else window.clearTimeout(id)
    })
    this.timers.clear()
    this.markToggle(false)
  }

  // The button is a hard on/off the pointer listeners must not undo.
  toggle() {
    this.paused = !this.paused
    if (this.paused) this.stop()
    else this.start()
  }

  shuffle() {
    ZONES.forEach(zone => {
      const items = this.zonesValue[zone] || []
      if (!items.length) return
      this.idx[zone] = Math.floor(Math.random() * items.length)
      this.render(zone)
    })
  }

  prev({ params: { zone } }) { this.step(zone, -1) }
  next({ params: { zone } }) { this.step(zone, 1) }

  step(zone, dir) {
    const items = this.zonesValue[zone] || []
    if (!items.length) return
    this.idx[zone] = (this.idx[zone] + dir + items.length) % items.length
    this.render(zone)
  }

  markToggle(playing) {
    if (!this.hasPlayToggleTarget) return
    this.playToggleTarget.setAttribute("aria-pressed", String(!playing))
  }

  render(zone) {
    const items = this.zonesValue[zone] || []
    const item = items[this.idx[zone]]
    const overlay = this.element.querySelector(`.zone--${zone} img`)
    const nameEl = this.element.querySelector(`[data-zone-label="${zone}"]`)
    const countEl = this.element.querySelector(`[data-zone-count="${zone}"]`)
    const whyEl = this.element.querySelector(`[data-zone-why="${zone}"]`)
    const pickEl = this.element.querySelector(`[data-zone-pick="${zone}"]`)

    if (overlay) {
      if (item?.url) {
        overlay.src = item.url
        overlay.alt = item.name || "Wardrobe item"
        overlay.style.opacity = "1"
      } else {
        overlay.removeAttribute("src")
        overlay.style.opacity = "0"
        overlay.alt = ""
      }
    }
    if (nameEl) nameEl.textContent = item?.name ?? "—"
    if (countEl) countEl.textContent = items.length ? `${this.idx[zone] + 1} / ${items.length}` : "none"
    if (whyEl) whyEl.textContent = item?.why ?? ""
    // Empty rather than absent: the form posts a fixed four inputs and the
    // server drops the blanks, so a zone with no garment saves as three items.
    if (pickEl) pickEl.value = item?.id ?? ""
  }
}
