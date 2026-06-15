import { incrementVisitCount } from "pwa/offline_store"

const RELOAD_BANNER_ID = "pwa-update-banner"

function showReloadBanner() {
  if (document.getElementById(RELOAD_BANNER_ID)) return
  const banner = document.createElement("div")
  banner.id = RELOAD_BANNER_ID
  banner.className = "pwa-update-banner"
  banner.setAttribute("role", "status")
  banner.innerHTML = `<span>New version available</span><button type="button" class="btn btn-primary btn-sm">Reload</button>`
  banner.querySelector("button").addEventListener("click", () => window.location.reload())
  document.body.appendChild(banner)
}

export async function bootPwa() {
  if (!("serviceWorker" in navigator)) return

  incrementVisitCount().catch(() => {})

  try {
    const registration = await navigator.serviceWorker.register("/service-worker")
    await registerPeriodicSync(registration)
    await requestPersistentStorage()
  } catch (_) {
    // SW registration can fail in dev without HTTPS
  }

  navigator.serviceWorker.addEventListener("message", event => {
    if (event.data?.type === "RELOAD_SUGGESTED") showReloadBanner()
  })

  navigator.serviceWorker.ready.then(registration => {
    registration.addEventListener("updatefound", () => {
      const worker = registration.installing
      if (!worker) return
      worker.addEventListener("statechange", () => {
        if (worker.state === "installed" && navigator.serviceWorker.controller) showReloadBanner()
      })
    })
  })
}

async function registerPeriodicSync(registration) {
  if (!("periodicSync" in registration)) return
  try {
    const tags = ["feed-prewarm", "badge-refresh"]
    for (const tag of tags) {
      await registration.periodicSync.register(tag, { minInterval: 24 * 60 * 60 * 1000 })
    }
  } catch (_) {
    // Permission or browser support varies
  }
}

async function requestPersistentStorage() {
  if (!navigator.storage?.persist) return
  try { await navigator.storage.persist() } catch (_) {}
}

bootPwa()