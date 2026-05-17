import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { zones: Object }

  connect() {
    this.idx = { head: 0, top: 0, bottom: 0, shoes: 0 }
    Object.keys(this.idx).forEach(z => this.render(z))
  }

  prev({ params: { zone } }) { this.step(zone, -1) }
  next({ params: { zone } }) { this.step(zone, 1) }

  step(zone, dir) {
    const items = this.zonesValue[zone] || []
    if (!items.length) return
    this.idx[zone] = (this.idx[zone] + dir + items.length) % items.length
    this.render(zone)
  }

  render(zone) {
    const items = this.zonesValue[zone] || []
    const item = items[this.idx[zone]]
    const overlay = this.element.querySelector(`.zone--${zone} img`)
    const nameEl = this.element.querySelector(`[data-zone-label="${zone}"]`)
    const countEl = this.element.querySelector(`[data-zone-count="${zone}"]`)

    if (overlay) {
      if (item?.url) {
        overlay.src = item.url
        overlay.alt = item.name
        overlay.style.opacity = "1"
      } else {
        overlay.src = ""
        overlay.style.opacity = "0"
      }
    }
    if (nameEl) nameEl.textContent = item?.name ?? "—"
    if (countEl && items.length) countEl.textContent = `${this.idx[zone] + 1} / ${items.length}`
    else if (countEl) countEl.textContent = "none"
  }
}
