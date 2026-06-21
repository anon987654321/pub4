import { BackgroundSyncPlugin } from "workbox-background-sync"
import { CacheableResponsePlugin } from "workbox-cacheable-response"
import { clientsClaim, setCacheNameDetails } from "workbox-core"
import { ExpirationPlugin } from "workbox-expiration"
import { cleanupOutdatedCaches, precacheAndRoute } from "workbox-precaching"
import { registerRoute, setCatchHandler } from "workbox-routing"
import { CacheFirst, NetworkFirst, NetworkOnly } from "workbox-strategies"

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
  networkTimeoutSeconds: 4,
  plugins: [
    new CacheableResponsePlugin({ statuses: [0, 200] }),
    new ExpirationPlugin({ maxEntries: 40, maxAgeSeconds: 24 * 60 * 60 }),
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

setCatchHandler(async ({ request }) => {
  if (request.mode === "navigate") {
    return (await caches.match(OFFLINE_URL)) || Response.error()
  }
  return Response.error()
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
    icon: "/icon.png",
    badge: "/icon.png",
    data: { url: data.url || "/" },
  }))
})

self.addEventListener("notificationclick", event => {
  event.notification.close()
  const target = event.notification.data?.url || "/"
  event.waitUntil(clients.matchAll({ type: "window", includeUncontrolled: true }).then(windows => {
    const open = windows.find(windowClient => new URL(windowClient.url).pathname === target)
    return open ? open.focus() : clients.openWindow(target)
  }))
})
