import { Controller } from "@hotwired/stimulus"

const STORE_NAME = "snapshots"

export default class extends Controller {
  static targets = ["list"]
  static values = { storageKey: String }

  connect() {
    this.load()
  }

  async load() {
    if (!("indexedDB" in window)) {
      this.renderEmpty()
      return
    }

    try {
      const items = await this.readSnapshots()
      this.render(items)
    } catch {
      this.renderEmpty()
    }
  }

  dbName() {
    return `${this.storageKeyValue}-idb-keyval`
  }

  openDb() {
    return new Promise((resolve, reject) => {
      const request = indexedDB.open(this.dbName(), 1)
      request.onupgradeneeded = () => {
        const db = request.result
        if (!db.objectStoreNames.contains(STORE_NAME)) db.createObjectStore(STORE_NAME)
      }
      request.onsuccess = () => resolve(request.result)
      request.onerror = () => reject(request.error)
    })
  }

  readSnapshots() {
    return this.openDb().then(db => new Promise((resolve, reject) => {
      const tx = db.transaction(STORE_NAME, "readonly")
      const request = tx.objectStore(STORE_NAME).get(this.storageKeyValue)
      request.onsuccess = () => resolve(request.result || [])
      request.onerror = () => reject(request.error)
      tx.oncomplete = () => db.close()
    }))
  }

  render(items) {
    if (!items.length) {
      this.renderEmpty()
      return
    }

    this.listTarget.innerHTML = items.map(item => `
      <li class="offline-page-item">
        <a href="${this.escape(item.url)}">${this.escape(item.title)}</a>
        <div class="offline-page-meta">${this.escape(item.meta || "")}</div>
      </li>
    `).join("")
  }

  renderEmpty() {
    this.listTarget.innerHTML = '<li class="offline-page-item">No cached items yet.</li>'
  }

  escape(value) {
    return String(value || "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
  }
}