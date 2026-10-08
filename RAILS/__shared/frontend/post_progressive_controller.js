import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["step", "indicator", "mediaInput", "publishing"]

  connect() {
    this.index = 0
    this.steps = this.stepTargets
    this.indicators = this.indicatorTargets
    this.onSubmitStart = () => this.#publishing(true)
    this.onSubmitEnd = (event) => {
      if (!event.detail?.success) this.#publishing(false)
    }
    this.element.addEventListener("turbo:submit-start", this.onSubmitStart)
    this.element.addEventListener("turbo:submit-end", this.onSubmitEnd)
    this.mediaInputTargets.forEach((input) => {
      input.addEventListener("change", this.mediaChanged)
    })
    this.#show(0)
  }

  disconnect() {
    this.mediaInputTargets.forEach((input) => {
      input.removeEventListener("change", this.mediaChanged)
    })
    this.element.removeEventListener("turbo:submit-start", this.onSubmitStart)
    this.element.removeEventListener("turbo:submit-end", this.onSubmitEnd)
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

  #publishing(active) {
    if (!this.hasPublishingTarget) return

    this.publishingTarget.hidden = !active
    this.element.setAttribute("aria-busy", active ? "true" : "false")
    this.element.dataset.publishing = active ? "true" : "false"
    this.steps.forEach((step) => { step.hidden = active || this.steps.indexOf(step) !== this.index })
    this.indicators.forEach((indicator) => { indicator.hidden = active })
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

    const input = this.steps[this.index]?.querySelector("input[type='text'], textarea, [contenteditable='true']")
    if (this.index === 1 && input && !input.value) input.focus({ preventScroll: true })
  }
}
