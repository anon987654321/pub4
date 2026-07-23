// Hide the bottom tab bar on scroll-down to free up feed space, reveal it
// on scroll-up -- ported behavior from the real 2014 mobile.css
// "Hide bars on scroll to free up space" (footer.slide_down), adapted to
// this app's actual scroll container (.app-shell scrolls, not window).
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.lastY = this.element.scrollTop
    this.ticking = false
    this.threshold = 8 // px of travel before reacting, avoids jitter at rest

    this.onScroll = this.onScroll.bind(this)
    this.element.addEventListener("scroll", this.onScroll, { passive: true })
  }

  disconnect() {
    this.element.removeEventListener("scroll", this.onScroll)
  }

  onScroll() {
    if (this.ticking) return
    this.ticking = true
    requestAnimationFrame(() => {
      const y = this.element.scrollTop
      const dy = y - this.lastY
      if (Math.abs(dy) > this.threshold) {
        document.documentElement.classList.toggle("chrome-hidden", dy > 0 && y > this.threshold)
        this.lastY = y
      }
      this.ticking = false
    })
  }
}
