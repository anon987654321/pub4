// Shared Hotwire baseline — Turbo Drive config, PWA shell, web-vitals sample (Rails 8 + Hotwire).
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

// --- Web vitals (1% sample) — recovered from x-parity stack ---
const WEB_VITALS_SAMPLE_RATE = 0.01

const webVitalsSampled = () => {
  if (window.__pub4WebVitalsSampled == null) {
    window.__pub4WebVitalsSampled = Math.random() < WEB_VITALS_SAMPLE_RATE
  }
  return window.__pub4WebVitalsSampled
}

const relayWebVitals = (metrics, path) => {
  const { lcp, inp, cls } = metrics
  if (lcp == null && inp == null && cls == null) return

  const body = new URLSearchParams({
    lcp: lcp ?? "",
    inp: inp ?? "",
    cls: cls ?? "",
    path
  })

  if (navigator.sendBeacon) {
    navigator.sendBeacon("/web_vitals", body)
    return
  }

  fetch("/web_vitals", {
    method: "POST",
    body,
    keepalive: true,
    headers: { "Content-Type": "application/x-www-form-urlencoded" }
  }).catch(() => {})
}

const observeWebVitalsFallback = (metrics, report) => {
  const observers = []

  const observe = (type, handler) => {
    try {
      const observer = new PerformanceObserver((list) => {
        handler(list.getEntries())
      })
      observer.observe({ type, buffered: true })
      observers.push(observer)
    } catch {
      // unsupported metric type in this browser
    }
  }

  observe("largest-contentful-paint", (entries) => {
    const last = entries.at(-1)
    if (!last) return
    metrics.lcp = Math.round(last.startTime)
    report()
  })

  let clsScore = 0
  observe("layout-shift", (entries) => {
    entries.forEach((entry) => {
      if (!entry.hadRecentInput) clsScore += entry.value
    })
    metrics.cls = Number(clsScore.toFixed(3))
    report()
  })

  let maxInp = null
  const trackInp = (duration) => {
    const ms = Math.round(duration)
    if (maxInp == null || ms > maxInp) {
      maxInp = ms
      metrics.inp = ms
      report()
    }
  }

  observe("event", (entries) => {
    entries.forEach((entry) => {
      if (!entry.interactionId) return
      const delay = entry.processingStart - entry.startTime
      trackInp(delay + entry.duration)
    })
  })

  observe("first-input", (entries) => {
    const entry = entries[0]
    if (!entry) return
    trackInp(entry.processingStart - entry.startTime)
  })

  return () => observers.forEach((observer) => observer.disconnect())
}

const observeWebVitals = (metrics, report) =>
  import("web-vitals")
    .then(({ onLCP, onINP, onCLS }) => {
      onLCP((metric) => {
        metrics.lcp = Math.round(metric.value)
        report()
      })
      onINP((metric) => {
        metrics.inp = Math.round(metric.value)
        report()
      })
      onCLS((metric) => {
        metrics.cls = Number(metric.value.toFixed(3))
        report()
      })
      return () => {}
    })
    .catch(() => observeWebVitalsFallback(metrics, report))

const bootWebVitalsSampling = () => {
  if (!webVitalsSampled()) return

  let teardown = () => {}
  let metrics = { lcp: null, inp: null, cls: null }
  let path = window.location.pathname

  const report = () => relayWebVitals(metrics, path)

  const arm = () => {
    teardown()
    metrics = { lcp: null, inp: null, cls: null }
    path = window.location.pathname
    observeWebVitals(metrics, report).then((stop) => {
      teardown = stop
    })
  }

  document.addEventListener("visibilitychange", () => {
    if (document.visibilityState === "hidden") report()
  })
  window.addEventListener("pagehide", report)
  document.addEventListener("turbo:load", arm)
  arm()
}

bootWebVitalsSampling()
