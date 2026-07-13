// Lightweight scroll reveal for timelines, phases, and long content
// Inspired by calm scrollytelling (The Pudding style + luxury restraint)
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    if (!('IntersectionObserver' in window)) return

    const observer = new IntersectionObserver((entries) => {
      entries.forEach(entry => {
        if (entry.isIntersecting) {
          entry.target.classList.add('is-visible')
          observer.unobserve(entry.target)
        }
      })
    }, { threshold: 0.12, rootMargin: "0px 0px -10% 0px" })

    this.element.querySelectorAll('.timeline-item, .style-phase-card').forEach(el => {
      observer.observe(el)
    })
  }
}