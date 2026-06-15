import { Controller } from "@hotwired/stimulus"
import { getFeedItems } from "pwa/offline_store"

export default class extends Controller {
  static targets = ["list", "section"]
  static values = { keys: Array }

  async connect() {
    const groups = await Promise.all((this.keysValue.length ? this.keysValue : ["posts"]).map(k => getFeedItems(k)))
    const items = groups.flat().slice(0, 20)
    if (!items.length || !this.hasListTarget) return
    if (this.hasSectionTarget) this.sectionTarget.hidden = false
    this.listTarget.innerHTML = items.map(item => `
      <li>
        <a href="${item.url}">${item.title}</a>
        ${item.meta ? `<span>${item.meta}</span>` : ""}
      </li>
    `).join("")
  }
}