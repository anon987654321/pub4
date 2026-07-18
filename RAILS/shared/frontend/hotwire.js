// Shared Hotwire baseline — Turbo Drive config, PWA shell (Rails 8 + Hotwire handbook).
import "@hotwired/turbo-rails"
import { bootThemeMeta } from "pub4/theme_meta"

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
  // Prefer .js path (MIME-stable); fall back to extensionless Rails route.
  const register = (path) =>
    navigator.serviceWorker.register(path, { scope: "/", updateViaCache: "none" })

  register("/service-worker.js").catch(() => register("/service-worker").catch(() => {}))
}


