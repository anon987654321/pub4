import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { options: Object }

  connect() {
    const options = { ...this.defaultOptions, ...(this.optionsValue || {}) }
    const slides = Array.from(this.element.children)

    this.element.style.overflowX = options.overflowX || "auto"
    this.element.style.scrollSnapType = options.scrollSnapType || "x mandatory"
    this.element.style.scrollBehavior = options.scrollBehavior || "smooth"
    if (options.spaceBetween) this.element.style.gap = `${options.spaceBetween}px`

    slides.forEach((slide) => {
      slide.style.scrollSnapAlign = options.scrollSnapAlign || "start"
      slide.style.flex = options.slidesPerView === "auto" ? "0 0 auto" : "0 0 100%"
    })

    this.swiper = {
      el: this.element,
      slides,
      slideNext: () => this.element.scrollBy({ left: this.element.clientWidth, behavior: "smooth" }),
      slidePrev: () => this.element.scrollBy({ left: -this.element.clientWidth, behavior: "smooth" }),
      update: () => this.refresh(),
      destroy: () => this.disconnect(),
    }
  }

  refresh() {
    const options = { ...this.defaultOptions, ...(this.optionsValue || {}) }
    Array.from(this.element.children).forEach((slide) => {
      slide.style.scrollSnapAlign = options.scrollSnapAlign || "start"
      slide.style.flex = options.slidesPerView === "auto" ? "0 0 auto" : "0 0 100%"
    })
  }

  disconnect() {
    this.swiper = null
    Array.from(this.element.children).forEach((slide) => {
      slide.style.removeProperty("scroll-snap-align")
      slide.style.removeProperty("flex")
    })
    this.element.style.removeProperty("overflow-x")
    this.element.style.removeProperty("scroll-snap-type")
    this.element.style.removeProperty("scroll-behavior")
    this.element.style.removeProperty("gap")
  }

  get defaultOptions() {
    return {}
  }
}
