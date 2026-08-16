import { BackgroundSyncPlugin } from "workbox-background-sync"
import { CacheableResponsePlugin } from "workbox-cacheable-response"
import { clientsClaim, setCacheNameDetails } from "workbox-core"
import { ExpirationPlugin } from "workbox-expiration"
import { cleanupOutdatedCaches, precacheAndRoute } from "workbox-precaching"
import { registerRoute, setCatchHandler } from "workbox-routing"
import { CacheFirst, NetworkFirst, NetworkOnly, StaleWhileRevalidate } from "workbox-strategies"

const APP_NAME = __APP_NAME__
const CACHE_VERSION = "__CACHE_VERSION__"
const OFFLINE_URL = "/offline"
const FORM_QUEUE = `${APP_NAME}-offline-forms`

setCacheNameDetails({ prefix: APP_NAME, suffix: CACHE_VERSION })
precacheAndRoute(self.__WB_MANIFEST, { cleanURLs: false })
cleanupOutdatedCaches()
clientsClaim()
self.skipWaiting()

const pages = new NetworkFirst({
  cacheName: `${APP_NAME}-pages-${CACHE_VERSION}`,
  networkTimeoutSeconds: 20,
  plugins: [
    new CacheableResponsePlugin({ statuses: [0, 200] }),
    new ExpirationPlugin({ maxEntries: 40, maxAgeSeconds: 24 * 60 * 60 }),
  ],
})

const dynamic = new StaleWhileRevalidate({
  cacheName: `${APP_NAME}-dynamic-${CACHE_VERSION}`,
  plugins: [
    new CacheableResponsePlugin({ statuses: [0, 200] }),
    new ExpirationPlugin({ maxEntries: 80, maxAgeSeconds: 12 * 60 * 60 }),
  ],
})

const assets = new CacheFirst({
  cacheName: `${APP_NAME}-assets-${CACHE_VERSION}`,
  plugins: [
    new CacheableResponsePlugin({ statuses: [0, 200] }),
    new ExpirationPlugin({ maxEntries: 160, maxAgeSeconds: 30 * 24 * 60 * 60 }),
  ],
})

registerRoute(({ request }) => request.mode === "navigate", pages)

registerRoute(
  ({ request, url }) => {
    if (url.origin !== self.location.origin) return false
    if (request.mode === "navigate") return false

    const path = url.pathname
    return (
      path.startsWith("/feed") ||
      path.startsWith("/activity") ||
      path.startsWith("/nearby") ||
      path.startsWith("/listings") ||
      path.startsWith("/outfits") ||
      path.startsWith("/items") ||
      path.startsWith("/posts") ||
      path.includes(".json") ||
      (request.destination === "" && request.headers.get("Accept")?.includes("application/json"))
    )
  },
  dynamic
)

registerRoute(
  ({ request, url }) => url.origin === self.location.origin &&
    ["style", "script", "worker", "image", "font"].includes(request.destination),
  assets
)
registerRoute(
  ({ request, url }) => request.method === "POST" && url.origin === self.location.origin,
  new NetworkOnly({
    plugins: [new BackgroundSyncPlugin(FORM_QUEUE, { maxRetentionTime: 24 * 60 })],
  }),
  "POST"
)

setCatchHandler(async ({ event, request }) => {
  if (request.mode !== "navigate") return Response.error()
  try {
    return await pages.handle({ event, request })
  } catch (_error) {
    const cached =
      (await caches.match(request)) ||
      (await caches.match("/")) ||
      (await caches.match(OFFLINE_URL))
    if (cached) return cached
    return Response.error()
  }
})

self.addEventListener("install", event => {
  event.waitUntil(caches.open(`${APP_NAME}-shell-${CACHE_VERSION}`).then(cache => cache.addAll(["/", OFFLINE_URL])))
})

self.addEventListener("periodicsync", event => {
  if (event.tag === "feed-prewarm") {
    event.waitUntil(pages.handleAll({ event, request: new Request("/") }).then(([, done]) => done))
    return
  }
  if (event.tag === "badge-refresh") {
    event.waitUntil(fetch("/notifications/badge")
      .then(response => response.ok ? response.json() : { unread_count: 0 })
      .then(data => self.registration.setAppBadge?.(data.unread_count || 0))
      .catch(() => {}))
  }
})

self.addEventListener("push", event => {
  const data = event.data?.json() || {}
  event.waitUntil(self.registration.showNotification(data.title || APP_NAME, {
    body: data.body || "",
    actions: data.actions || [],
    // The badge is the small monochrome glyph Android punches into the status
    // bar; a full-colour icon there renders as a grey blob. brgen's hand-rolled
    // worker had this right and the shared one did not, so this arrives with
    // brgen rather than being lost on the way in. All three apps ship both files.
    icon: "/icon-192.png",
    badge: "/icon-mono-192.png",
    data: { url: data.url || "/" },
  }))
})

self.addEventListener("notificationclick", event => {
  event.notification.close()

  const data = event.notification.data || {}
  const action = event.action
  let target = data.url || "/"

  if (action === "view" || action === "open") {
    target = data.url || "/"
  } else if (action && data.actions?.[action]) {
    target = data.actions[action]
  }

  event.waitUntil(
    clients.matchAll({ type: "window", includeUncontrolled: true }).then(windows => {
      const open = windows.find(w => new URL(w.url).pathname === new URL(target, self.location.origin).pathname)
      return open ? open.focus() : clients.openWindow(target)
    })
  )
})
