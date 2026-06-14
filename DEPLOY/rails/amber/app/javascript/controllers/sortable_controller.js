import Sortable from "@stimulus-components/sortable"
import { FetchRequest } from "@rails/request.js"

export default class extends Sortable {
  async onUpdate() {
    const url = this.element.dataset.sortableUpdateUrlValue
    if (!url) return

    const positions = this.sortable.toArray()
    const body = new FormData()
    positions.forEach(id => body.append("positions[]", id))

    await new FetchRequest(this.methodValue, url, {
      body,
      responseKind: this.responseKindValue
    }).perform()
  }
}
