import { Controller } from "@hotwired/stimulus"
import { saveDraft, loadDraft, clearDraft } from "pwa/offline_store"

export default class extends Controller {
  static targets = ["status"]
  static values = {
    key: String,
    debounce: { type: Number, default: 5000 }
  }

  timer = null

  async connect() {
    if (!this.keyValue) return
    const draft = await loadDraft(this.keyValue)
    if (!draft) return
    this.#restoreFields(draft.fields || {})
    this.#setStatus("Restored offline draft")
  }

  save() {
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.#persist(), this.debounceValue)
  }

  async clear() {
    await clearDraft(this.keyValue)
    this.#setStatus("Draft cleared")
  }

  async #persist() {
    const fields = this.#collectFields()
    await saveDraft(this.keyValue, { fields })
    this.#setStatus("Saved offline")
    if ("serviceWorker" in navigator && "SyncManager" in window) {
      const reg = await navigator.serviceWorker.ready
      await reg.sync?.register("offline-queue").catch(() => {})
    }
  }

  #collectFields() {
    const fields = {}
    this.element.querySelectorAll("input[name], textarea[name], select[name]").forEach(el => {
      if (!el.name || el.type === "password" || el.type === "file") return
      fields[el.name] = el.value
    })
    return fields
  }

  #restoreFields(fields) {
    Object.entries(fields).forEach(([name, value]) => {
      const el = this.element.querySelector(`[name="${CSS.escape(name)}"]`)
      if (el && el.value === "") el.value = value
    })
  }

  #setStatus(text) {
    if (this.hasStatusTarget) this.statusTarget.textContent = text
  }
}