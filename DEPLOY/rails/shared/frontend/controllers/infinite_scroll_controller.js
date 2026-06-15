import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["sentinel", "frame"]
  static values = { url: String, page: { type: Number, default: 1 } }

  connect() {
    this.observer = new IntersectionObserver(entries => {
      entries.forEach(entry => {
        if (entry.isIntersecting) this.loadMore()
      })
    }, { rootMargin: "200px" })
    if (this.hasSentinelTarget) this.observer.observe(this.sentinelTarget)
  }

  disconnect() {
    this.observer?.disconnect()
  }

  loadMore() {
    const next = this.pageValue + 1
    const url = new URL(this.urlValue || window.location.href, window.location.origin)
    url.searchParams.set("page", next)
    if (this.hasFrameTarget) {
      this.frameTarget.src = url.toString()
      this.pageValue = next
    }
  }
}