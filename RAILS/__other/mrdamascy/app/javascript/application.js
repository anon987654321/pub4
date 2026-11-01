// Mr. Damascy — entry point: Turbo Drive + Streams, then Stimulus controllers.
import "@hotwired/turbo-rails"
import "controllers"

// PWA: install the service worker once per session (§7).
if ("serviceWorker" in navigator && !window.__damascyServiceWorker) {
  window.__damascyServiceWorker = true
  window.addEventListener("turbo:load", () => {
    navigator.serviceWorker.register("/service-worker.js", { scope: "/" }).catch(() => {})
  })
}
