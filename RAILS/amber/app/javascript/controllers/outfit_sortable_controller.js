import Sortable from "@stimulus-components/sortable"
import { FetchRequest } from "@rails/request.js"

// An outfit saves its whole order in one request: the garment ids, top to
// bottom, to OutfitsController#reorder. The shared sortable sends one item's
// position to that item's own URL, which an outfit's garments do not carry, so
// this controller has its own identifier rather than the shared one.
export default class extends Sortable {
  static values = { updateUrl: String }

  async onUpdate() {
    if (!this.hasUpdateUrlValue) return

    const body = new FormData()
    this.sortable.toArray().forEach(id => body.append("positions[]", id))

    await new FetchRequest(this.methodValue, this.updateUrlValue, {
      body,
      responseKind: this.responseKindValue
    }).perform()
  }
}
