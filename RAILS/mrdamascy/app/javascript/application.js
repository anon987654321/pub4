// Mr. Damascy — entry point: Turbo Drive + Streams, then Stimulus controllers.
import "@hotwired/turbo-rails"
import "controllers"

// PWA: install the service worker once per page load (§7). This module runs
// once; Turbo visits after it must not register again.
if ("serviceWorker" in navigator) {
  const { serviceWorker } = navigator
  serviceWorker.register("/service-worker.js", { scope: "/" }).catch(() => {})
}
