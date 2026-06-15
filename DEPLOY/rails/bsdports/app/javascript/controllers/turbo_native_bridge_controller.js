import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  share(event) {
    const data = { title: event.params.title, url: event.params.url }
    if (window.Turbo?.navigator?.delegate?.adapter?.share) {
      window.Turbo.navigator.delegate.adapter.share(data)
    } else if (navigator.share) {
      navigator.share(data)
    }
  }

  presentSheet(event) {
    this.element.dispatchEvent(new CustomEvent("native:sheet", { detail: { url: event.params.url }, bubbles: true }))
  }
}