import { Controller } from "@hotwired/stimulus"

// Offline retry: the service worker answers a failed navigation with the
// offline page at the URL that failed, so retrying that URL, not the menu
// root (which fails offline too), is what brings the reader back.
export default class extends Controller {
  connect() {
    this.element.href = window.location.href
  }
}
