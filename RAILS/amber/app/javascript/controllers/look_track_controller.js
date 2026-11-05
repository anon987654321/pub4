import { Controller } from "@hotwired/stimulus"

// A home look's track steps one slide at a time: the arrow keys while the
// track has focus, and the previous/next buttons beside it. The browser's own
// arrow-key scroll moved a few pixels and left the snap to settle somewhere
// near; a step lands on the next slide's start. Each button is disabled at
// its end of the track, so a press always moves something.
export default class extends Controller {
  static targets = ["track", "previous", "next", "steps"]

  connect() {
    if (this.hasStepsTarget) this.stepsTarget.hidden = false
    this.sync = () => this.update()
    this.trackTarget.addEventListener("scroll", this.sync, { passive: true })
    this.update()
  }

  disconnect() {
    this.trackTarget.removeEventListener("scroll", this.sync)
  }

  previous() { this.step(-1) }
  next() { this.step(1) }

  key(event) {
    const direction = { ArrowLeft: -1, ArrowRight: 1 }[event.key]
    if (!direction) return
    event.preventDefault()
    this.step(direction)
  }

  step(direction) {
    const slides = Array.from(this.trackTarget.children)
    const current = this.currentIndex(slides)
    const target = slides[Math.min(Math.max(current + direction, 0), slides.length - 1)]
    if (!target) return
    const reduced = window.matchMedia?.("(prefers-reduced-motion: reduce)")?.matches
    this.trackTarget.scrollTo({ left: this.offsetOf(target), behavior: reduced ? "auto" : "smooth" })
  }

  // The slide whose start is nearest the track's scroll position.
  currentIndex(slides) {
    const left = this.trackTarget.scrollLeft
    let best = 0
    slides.forEach((slide, index) => {
      if (Math.abs(this.offsetOf(slide) - left) < Math.abs(this.offsetOf(slides[best]) - left)) best = index
    })
    return best
  }

  offsetOf(slide) {
    const first = this.trackTarget.firstElementChild
    return slide.offsetLeft - first.offsetLeft
  }

  update() {
    const track = this.trackTarget
    const end = track.scrollWidth - track.clientWidth
    if (this.hasPreviousTarget) this.previousTarget.disabled = track.scrollLeft <= 1
    if (this.hasNextTarget) this.nextTarget.disabled = track.scrollLeft >= end - 1
  }
}
