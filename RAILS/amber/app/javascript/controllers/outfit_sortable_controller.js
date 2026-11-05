import Sortable from "@stimulus-components/sortable"
import { FetchRequest } from "@rails/request.js"

// An outfit saves its whole order in one request: the garment ids, top to
// bottom, to OutfitsController#reorder. The shared sortable sends one item's
// position to that item's own URL, which an outfit's garments do not carry, so
// this controller has its own identifier rather than the shared one.
//
// Each save says how it went in the status line named by statusId, a live
// region outside the list (the list's children are the garments). A save that
// fails puts the garments back in the last order the server accepted, so the
// page never shows an order that is not the one stored.
export default class extends Sortable {
  static values = { updateUrl: String, statusId: String, savedLabel: String, failedLabel: String }

  connect() {
    super.connect()
    this.savedOrder = this.sortable.toArray()
  }

  async onUpdate() {
    if (!this.hasUpdateUrlValue) return

    const order = this.sortable.toArray()
    const body = new FormData()
    order.forEach(id => body.append("positions[]", id))

    let saved = false
    try {
      const response = await new FetchRequest(this.methodValue, this.updateUrlValue, {
        body,
        responseKind: this.responseKindValue
      }).perform()
      saved = response.ok
    } catch (_) {
      saved = false
    }

    if (saved) {
      this.savedOrder = order
    } else {
      this.sortable.sort(this.savedOrder, false)
      this.refreshKeyboardControls()
    }
    this.announce(saved ? this.savedLabelValue : this.failedLabelValue)
  }

  announce(text) {
    const status = this.hasStatusIdValue && document.getElementById(this.statusIdValue)
    if (status) status.textContent = text
  }
}
