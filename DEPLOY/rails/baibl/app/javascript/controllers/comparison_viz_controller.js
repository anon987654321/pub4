// comparison_viz_controller.js
// Wave 1 baibl improvement: interactive visualization for scripture comparisons (Bible/Quran/Gita etc.)
// Highlights concept threads and syncs with parallel text cards.

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { theme: String }

  connect() {
    this.element.querySelectorAll(".thread").forEach(thread => {
      thread.addEventListener("click", (e) => this.highlightConcept(e, thread))
      thread.addEventListener("mouseenter", () => this.previewConcept(thread))
    })
    console.log("[comparison-viz] ready for theme:", this.themeValue)
  }

  highlightConcept(event, threadEl) {
    const concept = threadEl.dataset.concept
    // Toggle active on thread
    threadEl.classList.toggle("active")
    // Find parallel cards and highlight matching content (demo: simple text match)
    this.element.closest(".compare-results, body").querySelectorAll(".trad-card").forEach(card => {
      const matches = card.textContent.toLowerCase().includes(concept.toLowerCase())
      card.style.outline = matches ? "2px solid #1d9bf0" : ""
      card.style.transition = "outline .2s"
      // Reset after short time for demo
      if (matches) setTimeout(() => { card.style.outline = "" }, 1400)
    })
  }

  previewConcept(threadEl) {
    // Lightweight preview: dim non-matching cards briefly
    const concept = threadEl.dataset.concept.toLowerCase()
    this.element.closest(".compare-results, body").querySelectorAll(".trad-card").forEach(card => {
      const has = card.textContent.toLowerCase().includes(concept)
      card.style.opacity = has ? "1" : "0.6"
    })
    setTimeout(() => {
      this.element.closest(".compare-results, body").querySelectorAll(".trad-card").forEach(c => c.style.opacity = "1")
    }, 600)
  }
}
