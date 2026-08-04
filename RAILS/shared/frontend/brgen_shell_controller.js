// City-name ticker + nav roving-tabindex + standalone-PWA chrome, as a real
// Stimulus controller instead of a global script wired to DOMContentLoaded/
// turbo:load with manual init-once flags -- same behavior, but lifecycle now
// follows connect()/disconnect() like every other controller in this app.
// (The decorative, pointer-events:none city ticker doesn't need a full
// touch-carousel library -- @stimulus-components/carousel wraps Swiper,
// which is built for swipeable slides, not a passive text cross-fade.)
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["carousel", "navSections"]

  connect() {
    this.reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches
    this.onVisibility = this.onVisibility.bind(this)
    this.onNavKeydown = this.onNavKeydown.bind(this)

    if (this.hasCarouselTarget) {
      this.slides = Array.from(this.carouselTarget.querySelectorAll(".carousel-slide"))
      this.slideIndex = 0
      this.syncCarouselPrefix()
      if (this.slides.length > 1 && !this.reduced) this.startCarousel()
      document.addEventListener("visibilitychange", this.onVisibility)
    }

    if (this.hasNavSectionsTarget) {
      this.navSectionsTarget.addEventListener("keydown", this.onNavKeydown)
    }

    this.syncStandaloneMode()
  }

  disconnect() {
    this.stopCarousel()
    document.removeEventListener("visibilitychange", this.onVisibility)
    if (this.hasNavSectionsTarget) {
      this.navSectionsTarget.removeEventListener("keydown", this.onNavKeydown)
    }
  }

  onVisibility() {
    if (document.hidden) this.stopCarousel()
    else if (!this.reduced) this.startCarousel()
  }

  startCarousel() {
    this.stopCarousel()
    this.carouselTimer = setInterval(() => this.advanceCarousel(), 2800)
  }

  stopCarousel() {
    if (this.carouselTimer) clearInterval(this.carouselTimer)
    this.carouselTimer = null
  }

  advanceCarousel() {
    this.slides[this.slideIndex]?.classList.remove("active")
    this.slideIndex = (this.slideIndex + 1) % this.slides.length
    this.slides[this.slideIndex]?.classList.add("active")
  }

  // Every write here must be conditional. This runs from connect(), and the
  // slides sit inside the subtree Stimulus observes for [data-controller], so an
  // unconditional `s.textContent = ...` is a childList mutation that feeds the
  // observer that reconnects the controller that runs this method again. That
  // loop pegged a renderer at 100% CPU and hung brgen's system tests forever --
  // invisible because ci.rb excludes test/system. Assigning the value it already
  // holds still emits a mutation record, so equality is the guard, not laziness.
  syncCarouselPrefix() {
    this.slides.forEach((s) => {
      if (!s.dataset.base) s.dataset.base = (s.textContent || s.dataset.domain || "").trim()
    })
    const parts = location.hostname.split(".")
    const prefix = parts.length >= 3 && parts[0] !== "www" ? `${parts[0]}.` : ""
    this.slides.forEach((s) => {
      const base = s.dataset.base
      const label = prefix + base
      if (s.textContent !== label) s.textContent = label
      if (s.tagName === "A" && (!s.getAttribute("href") || s.getAttribute("href") === "#")) {
        s.href = `https://${base}/`
      }
    })
  }

  onNavKeydown(e) {
    const tabs = Array.from(this.navSectionsTarget.querySelectorAll('[role="tab"]'))
    const i = tabs.indexOf(document.activeElement)
    if (i < 0) return
    let next = i
    if (e.key === "ArrowRight" || e.key === "ArrowDown") next = (i + 1) % tabs.length
    else if (e.key === "ArrowLeft" || e.key === "ArrowUp") next = (i - 1 + tabs.length) % tabs.length
    else if (e.key === "Home") next = 0
    else if (e.key === "End") next = tabs.length - 1
    else return
    e.preventDefault()
    tabs.forEach((t, idx) => { t.tabIndex = idx === next ? 0 : -1 })
    tabs[next].focus()
  }

  syncStandaloneMode() {
    const standalone = window.matchMedia("(display-mode: standalone)").matches
    const mode = standalone ? "standalone" : "browser"
    // Conditional for the same reason as syncCarouselPrefix: <html> is the root
    // Stimulus observes, and re-setting an attribute to its current value still
    // queues a mutation record.
    if (document.documentElement.dataset.displayMode !== mode) {
      document.documentElement.dataset.displayMode = mode
    }
    document.querySelectorAll("nav").forEach((nav) => nav.classList.toggle("nav-visible", standalone))
  }
}
