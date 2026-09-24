import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.element.dataset.nativeShell = this.available() ? "true" : "false"
  }

  available() {
    return Boolean(window.webkit?.messageHandlers)
  }

  share(event) {
    const payload = {
      title: event.params.title || document.title,
      text: event.params.text || "",
      url: event.params.url || window.location.href
    }

    if (window.webkit?.messageHandlers?.pub4Share) {
      window.webkit.messageHandlers.pub4Share.postMessage(payload)
      return
    }

    if (navigator.share) {
      navigator.share(payload).catch(() => {})
    }
  }
}
