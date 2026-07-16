import { Controller } from "@hotwired/stimulus"
import { get, set, del } from "idb-keyval"

const STORE = "entries"
const QUEUE = "queue"

export default class extends Controller {
  static values = { key: String }

  connect() {
    this.saveTimer = null
    this.onInput = this.scheduleSave.bind(this)
    this.onOnline = this.flushQueue.bind(this)
    this.onSubmit = this.handleSubmit.bind(this)
    this.element.addEventListener("input", this.onInput)
    this.element.addEventListener("change", this.onInput)
    this.element.addEventListener("submit", this.onSubmit)
    window.addEventListener("online", this.onOnline)
    this.restore()
  }

  disconnect() {
    this.element.removeEventListener("input", this.onInput)
    this.element.removeEventListener("change", this.onInput)
    this.element.removeEventListener("submit", this.onSubmit)
    window.removeEventListener("online", this.onOnline)
    if (this.saveTimer) clearTimeout(this.saveTimer)
  }

  async handleSubmit(event) {
    if (navigator.onLine) {
      await this.clear()
      return
    }

    event.preventDefault()
    await this.enqueue(this.snapshot())
    await this.registerSync()
  }

  scheduleSave() {
    if (this.saveTimer) clearTimeout(this.saveTimer)
    this.saveTimer = setTimeout(() => this.save(), 150)
  }

  async restore() {
    const saved = await get(this.keyValue, STORE)
    if (!saved) return
    this.applySnapshot(saved)
  }

  async save() {
    await set(this.keyValue, this.snapshot(), STORE)
  }

  snapshot() {
    const fields = {}
    this.element.querySelectorAll("input, textarea, select").forEach(field => {
      if (!field.name || field.type === "file") return
      if (field.type === "checkbox") {
        fields[field.name] = field.checked ? "1" : "0"
        return
      }
      if (field.type === "radio") {
        if (field.checked) fields[field.name] = field.value
        return
      }
      fields[field.name] = field.value
    })
    return fields
  }

  applySnapshot(snapshot) {
    Object.entries(snapshot || {}).forEach(([name, value]) => {
      const fields = this.element.querySelectorAll(`[name="${CSS.escape(name)}"]`)
      fields.forEach(field => {
        if (field.type === "checkbox") field.checked = value === "1"
        else if (field.type === "radio") field.checked = field.value === value
        else field.value = value
      })
    })
  }

  async enqueue(payload) {
    const queue = (await get(this.keyValue, QUEUE)) || []
    queue.push({
      payload,
      queuedAt: Date.now(),
      action: this.element.action,
      method: this.element.method || "post",
      csrfToken: this.csrfToken()
    })
    await set(this.keyValue, queue, QUEUE)
  }

  async flushQueue() {
    const queue = (await get(this.keyValue, QUEUE)) || []
    if (!queue.length) return

    const remaining = []
    for (const entry of queue) {
      try {
        await fetch(entry.action, {
          method: entry.method.toUpperCase(),
          credentials: "same-origin",
          headers: {
            "Content-Type": "application/x-www-form-urlencoded;charset=UTF-8",
            "X-CSRF-Token": entry.csrfToken || ""
          },
          body: new URLSearchParams(entry.payload)
        })
      } catch (_error) {
        remaining.push(entry)
      }
    }

    await set(this.keyValue, remaining, QUEUE)
    if (!remaining.length) await this.clear()
  }

  async clear() {
    await Promise.all([del(this.keyValue, STORE), del(this.keyValue, QUEUE)])
  }

  async registerSync() {
    if (!("serviceWorker" in navigator) || !("SyncManager" in window)) return
    const reg = await navigator.serviceWorker.ready
    await reg.sync.register("draft-store").catch(() => {})
  }

  csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content || ""
  }
}