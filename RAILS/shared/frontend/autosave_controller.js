import { Controller } from "@hotwired/stimulus"
import { get, set } from "idb-keyval"

const STORE = "autosave"

export default class extends Controller {
  static values = {
    key: String,
    url: String,
    interval: { type: Number, default: 5000 },
    saving: { type: String, default: "Saving…" },
    saved: { type: String, default: "Saved" },
    savedLocally: { type: String, default: "Saved locally" },
    restored: { type: String, default: "Restored" }
  }

  static targets = ["status"]

  connect() {
    this.dirty = false
    this.onInput = this.markDirty.bind(this)
    this.onOnline = this.flush.bind(this)
    this.element.addEventListener("input", this.onInput)
    this.element.addEventListener("change", this.onInput)
    window.addEventListener("online", this.onOnline)
    this.intervalId = window.setInterval(() => this.flush(), this.intervalValue)
    this.restore()
  }

  disconnect() {
    this.element.removeEventListener("input", this.onInput)
    this.element.removeEventListener("change", this.onInput)
    window.removeEventListener("online", this.onOnline)
    if (this.intervalId) window.clearInterval(this.intervalId)
  }

  markDirty() {
    this.dirty = true
    this.setStatus(this.savingValue)
  }

  async restore() {
    const saved = await get(this.keyValue, STORE)
    if (!saved) return
    this.applySnapshot(saved)
    this.setStatus(this.restoredValue)
  }

  async flush() {
    if (!this.dirty) return

    const snapshot = this.snapshot()
    await set(this.keyValue, snapshot, STORE)

    if (!navigator.onLine || !this.hasUrlValue) {
      this.dirty = false
      this.setStatus(this.savedLocallyValue)
      return
    }

    const headers = {
      "Content-Type": "application/x-www-form-urlencoded;charset=UTF-8",
      "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content || ""
    }
    const response = await fetch(this.urlValue, {
      method: "PATCH",
      headers: headers,
      credentials: "same-origin",
      body: new URLSearchParams(snapshot)
    }).catch(() => null)

    if (response?.ok) {
      this.dirty = false
      this.setStatus(this.savedValue)
    } else {
      this.setStatus(this.savedLocallyValue)
    }
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

  setStatus(text) {
    if (!this.hasStatusTarget) return
    this.statusTarget.textContent = text
  }
}
