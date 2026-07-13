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

const bootMinimalGesture = () => {
  if (!document.body?.classList.contains("zen-minimal")) return
  if (window.__pub4MinimalGesture) return
  window.__pub4MinimalGesture = true
  import("pub4/minimal_gesture").then((module) => {
    if (typeof module.initMinimalUI === "function") module.initMinimalUI()
  })
}

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

document.addEventListener("turbo:load", () => {
  bootMinimalGesture()
  bootNavReveal()
})
bootMinimalGesture()
bootNavReveal()
bootWebVitalsSampling()
