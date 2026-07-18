// Carousel + standalone PWA chrome + nav keyboard (UI_REFINEMENTS pass).

class SimpleCarousel {
  constructor(el, ms = 2800) {
    this.el = el
    this.slides = Array.from(el.querySelectorAll(".carousel-slide"))
    this.i = 0
    this.n = this.slides.length
    this.ms = ms
    this.t = null
    this.reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches
    if (this.n > 1 && !this.reduced) this.start()
    document.addEventListener("visibilitychange", () => {
      if (document.hidden) this.stop()
      else if (!this.reduced) this.start()
    })
  }
  start() {
    this.stop()
    this.t = setInterval(() => this.next(), this.ms)
  }
  stop() {
    if (this.t) clearInterval(this.t)
    this.t = null
  }
  next() {
    this.slides[this.i]?.classList.remove("active")
    this.i = (this.i + 1) % this.n
    this.slides[this.i]?.classList.add("active")
  }
}

function updateCarouselPrefix() {
  const el = document.getElementById("cityCarousel")
  if (!el) return
  const slides = el.querySelectorAll(".carousel-slide")
  slides.forEach((s) => {
    if (!s.dataset.base) s.dataset.base = (s.textContent || s.dataset.domain || "").trim()
  })
  const parts = location.hostname.split(".")
  const prefix = parts.length >= 3 && parts[0] !== "www" ? `${parts[0]}.` : ""
  slides.forEach((s) => {
    const base = s.dataset.base
    if (s.tagName === "A") {
      s.textContent = prefix + base
      if (!s.getAttribute("href") || s.getAttribute("href") === "#") {
        s.href = `https://${base}/`
      }
    } else {
      s.textContent = prefix + base
    }
  })
}

function initCarousel() {
  const el = document.getElementById("cityCarousel")
  if (!el || el.__carouselInit) return
  el.__carouselInit = true
  new SimpleCarousel(el)
  updateCarouselPrefix()
}

function initNavKeyboard() {
  const bar = document.getElementById("nav_sections")
  if (!bar || bar.__keysInit) return
  bar.__keysInit = true
  const tabs = () => Array.from(bar.querySelectorAll('[role="tab"]'))
  bar.addEventListener("keydown", (e) => {
    const list = tabs()
    const i = list.indexOf(document.activeElement)
    if (i < 0) return
    let next = i
    if (e.key === "ArrowRight" || e.key === "ArrowDown") next = (i + 1) % list.length
    else if (e.key === "ArrowLeft" || e.key === "ArrowUp") next = (i - 1 + list.length) % list.length
    else if (e.key === "Home") next = 0
    else if (e.key === "End") next = list.length - 1
    else return
    e.preventDefault()
    list.forEach((t, idx) => {
      t.tabIndex = idx === next ? 0 : -1
    })
    list[next].focus()
  })
}

function syncStandaloneMode() {
  const standalone = window.matchMedia("(display-mode: standalone)").matches
  document.documentElement.dataset.displayMode = standalone ? "standalone" : "browser"
  document.querySelectorAll("nav").forEach((nav) => nav.classList.toggle("nav-visible", standalone))
}

function bootShell() {
  initCarousel()
  initNavKeyboard()
  syncStandaloneMode()
  updateCarouselPrefix()
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", bootShell)
} else {
  bootShell()
}

document.addEventListener("turbo:load", bootShell)
