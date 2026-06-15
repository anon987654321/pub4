import { Controller } from "@hotwired/stimulus"
import { cacheFeedItem } from "pwa/offline_store"

export default class extends Controller {
  static values = {
    key: String,
    title: String,
    url: String,
    meta: String
  }

  connect() {
    if (!this.keyValue || !this.urlValue) return
    cacheFeedItem(this.keyValue, {
      title: this.titleValue,
      url: this.urlValue,
      meta: this.metaValue
    }).catch(() => {})
  }
}