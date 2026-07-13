// Shared Hotwire baseline — Turbo Drive config, PWA shell, nav reveal (Rails 8 + Hotwire handbook).
import "@hotwired/turbo-rails"
import { bootThemeMeta } from "pub4/theme_meta"
import { bootNavReveal } from "pub4/nav_reveal"

bootThemeMeta()

if (window.Turbo?.config?.drive) {
  Turbo.config.drive.progressBarDelay = 100
}

const displayModeQuery = window.matchMedia("(display-mode: standalone)")

const syncStandaloneMode = () => {
  const standalone = displayModeQuery.matches
  document.documentElement.dataset.displayMode = standalone ? "standalone" : "browser"
  document.querySelectorAll("nav").forEach((nav) => {
    const primaryNavigation = nav.hasAttribute("data-pwa-primary-nav")
    nav.classList.toggle("nav-visible", standalone || primaryNavigation)
  })
}

syncStandaloneMode()
if (displayModeQuery.addEventListener) {
  displayModeQuery.addEventListener("change", syncStandaloneMode)
} else {
  displayModeQuery.addListener(syncStandaloneMode)
}

if ("serviceWorker" in navigator) {
  navigator.serviceWorker.register("/service-worker")
}

document.addEventListener("turbo:load", () => {
  bootNavReveal()
})
bootNavReveal()
