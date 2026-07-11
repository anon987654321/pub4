import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    if (!("IntersectionObserver" in window)) {
      this.element.classList.add("revealed")
      return
    }

    this.observer = new IntersectionObserver(entries => {
      entries.forEach(entry => {
        if (!entry.isIntersecting) return
        entry.target.classList.add("revealed")
        this.observer.unobserve(entry.target)
      })
    }, { rootMargin: "120px" })

    this.observer.observe(this.element)
  }

  disconnect() {
    if (this.observer) this.observer.disconnect()
  }
}
