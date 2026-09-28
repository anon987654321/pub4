import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["step", "indicator", "photoInput"]

  connect() {
    this.index = 0
    this.steps = this.stepTargets
    this.indicators = this.indicatorTargets
    this.photoInputTargets.forEach((input) => {
      input.addEventListener("change", this.mediaChanged)
    })
    this.#show(0)
  }

  disconnect() {
    this.photoInputTargets.forEach((input) => {
      input.removeEventListener("change", this.mediaChanged)
    })
  }

  next() {
    this.#show(this.index + 1)
  }

  back() {
    this.#show(this.index - 1)
  }

  skipMedia() {
    this.#show(1)
  }

  mediaChanged = (event) => {
    if (event.target.files?.length) this.#show(1)
  }

  #show(next) {
    if (!this.steps.length) return
    this.index = Math.max(0, Math.min(next, this.steps.length - 1))

    this.steps.forEach((step, index) => {
      step.hidden = index !== this.index
      step.setAttribute("aria-current", index === this.index ? "step" : "false")
    })

    this.indicators.forEach((indicator, index) => {
      const active = index === this.index
      indicator.classList.toggle("is-active", active)
      indicator.setAttribute("aria-current", active ? "step" : "false")
    })

    const heading = this.steps[this.index]?.querySelector("h2, legend, [data-post-progressive-heading]")
    heading?.focus?.({ preventScroll: true })
  }
}
