// Lightweight scroll reveal for timelines, phases, and sidebar cards.
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    revealClass: { type: String, default: "is-visible" }
  }

  connect() {
    if (!("IntersectionObserver" in window)) {
      this.element.classList.add(this.#revealClass())
      return
    }

    const observer = new IntersectionObserver((entries) => {
      entries.forEach((entry) => {
        if (!entry.isIntersecting) return
        entry.target.classList.add(this.#revealClass())
        observer.unobserve(entry.target)
      })
    }, {
      threshold: this.element.hasAttribute("data-minimal-reveal") ? 0 : 0.12,
      rootMargin: this.element.hasAttribute("data-minimal-reveal") ? "120px" : "0px 0px -10% 0px"
    })

    if (this.element.hasAttribute("data-minimal-reveal")) {
      observer.observe(this.element)
      return
    }

    const children = this.element.querySelectorAll(".timeline-item, .style-phase-card")
    if (children.length) {
      children.forEach((el) => observer.observe(el))
    } else {
      observer.observe(this.element)
    }
  }

  #revealClass() {
    return this.element.hasAttribute("data-minimal-reveal") ? "revealed" : this.revealClassValue
  }
}
