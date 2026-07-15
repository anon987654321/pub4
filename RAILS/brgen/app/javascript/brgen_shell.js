// Carousel prefix, guest splash dismiss, standalone PWA chrome — layout shell only.

class SimpleCarousel {
  constructor(el, ms = 2800) {
    this.slides = Array.from(el.querySelectorAll(".carousel-slide"))
    this.i = 0
    this.n = this.slides.length
    if (this.n > 1) this.t = setInterval(() => this.next(), ms)
  }
  next() {
    this.slides[this.i].classList.remove("active")
    this.i = (this.i + 1) % this.n
    this.slides[this.i].classList.add("active")
  }
}

function updateCarouselPrefix() {
  const el = document.getElementById("cityCarousel")
  if (!el) return
  const slides = el.querySelectorAll(".carousel-slide")
  slides.forEach(s => { if (!s.dataset.base) s.dataset.base = s.textContent.trim() })
  const parts = location.hostname.split(".")
  const prefix = parts.length >= 3 && parts[0] !== "www" ? `${parts[0]}.` : ""
  slides.forEach(s => { s.textContent = prefix + s.dataset.base })
}

function initCarousel() {
  const el = document.getElementById("cityCarousel")
  if (!el || el.__carouselInit) return
  el.__carouselInit = true
  new SimpleCarousel(el)
  updateCarouselPrefix()
}

function initSplash() {
  const splash = document.getElementById("splash")
  if (!splash || splash.__splashInit) return
  splash.__splashInit = true

  const dismiss = () => {
    if (splash.hidden) return
    splash.style.pointerEvents = "none"
    splash.classList.add("ack")
    const h2 = splash.querySelector("h2")
    if (h2) h2.classList.add("clicked")
    setTimeout(() => { splash.hidden = true; splash.classList.remove("ack") }, 220)
    navigator.vibrate?.(8)
  }

  splash.addEventListener("click", e => { e.stopPropagation(); dismiss() })
  splash.addEventListener("keydown", e => {
    if (e.code === "Enter" || e.code === "Space") { e.preventDefault(); dismiss() }
  })
  splash.focus()
}

function syncStandaloneMode() {
  const standalone = window.matchMedia("(display-mode: standalone)").matches
  document.documentElement.dataset.displayMode = standalone ? "standalone" : "browser"
  document.querySelectorAll("nav").forEach(nav => nav.classList.toggle("nav-visible", standalone))
}

function bootShell() {
  initCarousel()
  initSplash()
  syncStandaloneMode()
  updateCarouselPrefix()
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", bootShell)
} else {
  bootShell()
}

document.addEventListener("turbo:load", bootShell)