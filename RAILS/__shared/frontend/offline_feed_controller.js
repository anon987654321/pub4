// Snapshots a feed row into IndexedDB so /offline can list something real.
//
// This lived in brgen/app/javascript/controllers/ while amber's item card also
// emitted data-controller="offline-feed" — amber's importmap eager-loads only
// its own controllers/ dir, so every amber item silently registered nothing and
// amber's offline page had no snapshots to show. Shared, pinned, and registered
// in stimulus_boot, it resolves in all three apps.
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
