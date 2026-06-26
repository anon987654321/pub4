import { Controller } from "@hotwired/stimulus"
import { get, set } from "idb-keyval"

const STORE = "snapshots"

export default class extends Controller {
  static values = { key: String, title: String, url: String, meta: String }

  connect() {
    this.save()
  }

  async save() {
    const current = (await get(this.keyValue, STORE)) || []
    const next = [
      { title: this.titleValue, url: this.urlValue, meta: this.metaValue },
      ...current.filter(item => item.url !== this.urlValue)
    ].slice(0, 20)
    await set(this.keyValue, next, STORE)
  }
}
