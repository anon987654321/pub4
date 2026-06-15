import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { src: String, blurhash: String }

  connect() {
    this.observer = new IntersectionObserver(entries => {
      entries.forEach(entry => {
        if (!entry.isIntersecting) return
        this.load()
        this.observer.disconnect()
      })
    })
    this.observer.observe(this.element)
  }

  load() {
    const img = this.element
    if (this.blurhashValue) img.style.background = `url('data:image/svg+xml,<svg xmlns="http://www.w3.org/2000/svg"/>')`
    img.src = this.srcValue || img.dataset.src
    img.classList.add("lazy-image--loaded")
  }
}