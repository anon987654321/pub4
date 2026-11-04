import { Controller } from "@hotwired/stimulus"

// Menu chips: the chip of the section in view carries aria-current, so the
// sticky chip row shows where the reader is (and scrolls that chip into
// sight). A section counts as in view while it crosses the band just under
// the sticky bars.
export default class extends Controller {
  static targets = ["chip"]

  connect() {
    this.observer = new IntersectionObserver((entries) => this.seen(entries), {
      rootMargin: "-120px 0px -60% 0px",
    })
    this.chipTargets
      .map((chip) => document.getElementById(chip.getAttribute("href").slice(1)))
      .filter(Boolean)
      .forEach((section) => this.observer.observe(section))
  }

  disconnect() {
    this.observer.disconnect()
  }

  seen(entries) {
    const visible = entries.find((entry) => entry.isIntersecting)
    if (visible) this.mark(visible.target.id)
  }

  mark(id) {
    this.chipTargets.forEach((chip) => {
      const current = chip.getAttribute("href").slice(1) === id
      if (current) {
        chip.setAttribute("aria-current", "true")
        chip.scrollIntoView?.({ block: "nearest", inline: "nearest" })
      } else {
        chip.removeAttribute("aria-current")
      }
    })
  }
}
