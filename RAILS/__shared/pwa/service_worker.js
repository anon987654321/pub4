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
const DYNAMIC_PREFIXES = [
  "/feed",
  "/activity",
  "/nearby",
  "/listings",
  "/outfits",
  "/items",
  "/posts",
]

// A person's own pages: conversations, notifications, account and sign-in.
// They are never written to a cache, because a cache outlives the session —
// the next person on a shared phone, offline, would be served them.
const PRIVATE_PREFIXES = [
  "/conversations",
  "/messages",
  "/notifications",
  "/account",
  "/settings",
  "/session",
  "/registration",
  "/passwords",
  "/checkout",
  "/orders",
]
const isPrivatePath = path => PRIVATE_PREFIXES.some(prefix => path === prefix || path.startsWith(`${prefix}/`))

// Only writing something new is worth replaying after a dead connection: a
// post, a comment or reply, a message. Everything else — sign-in with its
// password, payment, deleting, settings — must not wait in IndexedDB and
// fire later on its own.
const REPLAYABLE_POST = /(^|\/)(posts|comments|replies|messages)$/

const clearPrivateCaches = async () => {
  const names = await caches.keys()
  await Promise.all(names.filter(name => /-(pages|dynamic)-/.test(name)).map(name => caches.delete(name)))
}

// Every deploy renamed pages/dynamic/assets with a new version suffix, and
// nothing ever deleted the old names - each device kept one full cache set
// per deploy it had ever seen, bounded only by per-cache maxEntries. On
// activation, drop every runtime cache that is not the current version. The
// precache is cleanupOutdatedCaches' job, and the offline-forms queue
// outlives deploys on purpose.
const RUNTIME_CACHE = new RegExp(`^${APP_NAME}-(pages|dynamic|assets)-`)
const pruneStaleRuntimeCaches = async () => {
  const keep = new Set([
    `${APP_NAME}-pages-${CACHE_VERSION}`,
    `${APP_NAME}-dynamic-${CACHE_VERSION}`,
    `${APP_NAME}-assets-${CACHE_VERSION}`,
  ])
  const names = await caches.keys()
  await Promise.all(
    names.filter(name => RUNTIME_CACHE.test(name) && !keep.has(name)).map(name => caches.delete(name)),
  )
}

const sanitizeTargetUrl = rawUrl => {
  if (!rawUrl || typeof rawUrl !== "string") return "/"

  try {
    const url = new URL(rawUrl, self.location.origin)
    if (url.origin !== self.location.origin) return "/"
    if (["javascript:", "data:", "about:", "blob:"].includes(url.protocol.toLowerCase())) return "/"
    return url.pathname + url.search + url.hash
  } catch (_error) {
    return "/"
  }
}

setCacheNameDetails({ prefix: APP_NAME, suffix: CACHE_VERSION })
precacheAndRoute(self.__WB_MANIFEST, { cleanURLs: false })
cleanupOutdatedCaches()
clientsClaim()
self.skipWaiting()

// Navigation preload: the browser starts a page's request while the worker
// boots, and Workbox's strategy handler answers a navigation with
// event.preloadResponse rather than fetching again, so NetworkFirst no longer
// waits for a cold worker before the request even leaves.
self.addEventListener("activate", event => {
  if (self.registration.navigationPreload) event.waitUntil(self.registration.navigationPreload.enable())
  event.waitUntil(pruneStaleRuntimeCaches())
})

// Four seconds, then the cached page or /offline: a reader on a dead train
// connection should not stare at a blank tab for twenty. Only 200 is cached;
// status 0 is an opaque response whose real status is hidden, so caching it
// can pin a failure in place of the page.
const pages = new NetworkFirst({
  cacheName: `${APP_NAME}-pages-${CACHE_VERSION}`,
  networkTimeoutSeconds: 4,
  plugins: [
    new CacheableResponsePlugin({ statuses: [200] }),
    new ExpirationPlugin({ maxEntries: 24, maxAgeSeconds: 12 * 60 * 60 }),
  ],
})

const dynamic = new StaleWhileRevalidate({
  cacheName: `${APP_NAME}-dynamic-${CACHE_VERSION}`,
  plugins: [
    new CacheableResponsePlugin({ statuses: [200] }),
    new ExpirationPlugin({ maxEntries: 32, maxAgeSeconds: 6 * 60 * 60 }),
  ],
})

const assets = new CacheFirst({
  cacheName: `${APP_NAME}-assets-${CACHE_VERSION}`,
  plugins: [
    new CacheableResponsePlugin({ statuses: [200] }),
    new ExpirationPlugin({ maxEntries: 120, maxAgeSeconds: 30 * 24 * 60 * 60 }),
  ],
})

registerRoute(({ request, url }) => request.mode === "navigate" && isPrivatePath(url.pathname), new NetworkOnly())
registerRoute(({ request }) => request.mode === "navigate", pages)

registerRoute(
  ({ request, url }) => {
    if (url.origin !== self.location.origin) return false
    if (request.mode === "navigate") return false

    const path = url.pathname
    if (isPrivatePath(path)) return false
    const isDynamicPath = DYNAMIC_PREFIXES.some(prefix => path.startsWith(prefix))
    const isJson = path.includes(".json") || (request.destination === "" && request.headers.get("Accept")?.includes("application/json"))
    return isDynamicPath || isJson
  },
  dynamic
)

registerRoute(
  ({ request, url }) => url.origin === self.location.origin &&
    ["style", "script", "worker", "image", "font"].includes(request.destination),
  assets
)
// Signing in or out (POST /session; the sign-out button rides _method=delete)
// starts a different person's session on this device: drop what the last one
// left in the page and data caches before the request goes out.
registerRoute(
  ({ url }) => url.origin === self.location.origin && url.pathname === "/session",
  async ({ request }) => {
    await clearPrivateCaches()
    return fetch(request)
  },
  "POST"
)
registerRoute(
  ({ request, url }) => request.method === "POST" && url.origin === self.location.origin &&
    REPLAYABLE_POST.test(url.pathname),
  new NetworkOnly({
    plugins: [new BackgroundSyncPlugin(FORM_QUEUE, { maxRetentionTime: 24 * 60 })],
  }),
  "POST"
)

setCatchHandler(async ({ event, request }) => {
  if (request.mode !== "navigate") return Response.error()
  // A private page that cannot load says so; it is never stood in for by
  // whatever public page happens to be cached.
  if (isPrivatePath(new URL(request.url).pathname)) return (await caches.match(OFFLINE_URL)) || Response.error()
  // The page itself if it was cached, else /offline. Never "/": the home page
  // can be a signed-in one, and the next person on the device would be served it.
  try {
    return await pages.handle({ event, request })
  } catch (_error) {
    const cached = (await caches.match(request)) || (await caches.match(OFFLINE_URL))
    if (cached) return cached
    return Response.error()
  }
})

// The page can ask for the same clean-up, e.g. after a sign-out that did not
// go through POST /session.
self.addEventListener("message", event => {
  if (event.data?.type === "clear-private-caches") event.waitUntil(clearPrivateCaches())
})

self.addEventListener("install", event => {
  // /offline only. "/" was here and in the precache manifest, fetched with the
  // installing visitor's cookies, so a signed-in home page sat in a cache that
  // outlives the session.
  event.waitUntil(caches.open(`${APP_NAME}-shell-${CACHE_VERSION}`).then(cache => cache.addAll([OFFLINE_URL])))
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

// Each action's address goes into the notification's own data, keyed by the
// action's name: showNotification keeps only action, title and icon of an
// action, so notificationclick has nowhere else to read it from.
const actionTargets = actions => Object.fromEntries(
  actions.filter(action => action?.action && action.url).map(action => [action.action, sanitizeTargetUrl(action.url)])
)

self.addEventListener("push", event => {
  const data = event.data?.json() || {}
  const actions = Array.isArray(data.actions) ? data.actions : []
  event.waitUntil(self.registration.showNotification(data.title || APP_NAME, {
    body: data.body || "",
    actions: actions.map(({ action, title, icon }) => ({ action, title, icon })),
    icon: data.icon || "/icon-192.png",
    badge: data.badge || "/icon-mono-192.png",
    data: { url: sanitizeTargetUrl(data.url || "/"), actions: actionTargets(actions) },
  }))
})

self.addEventListener("notificationclick", event => {
  event.notification.close()

  const data = event.notification.data || {}
  const action = event.action
  let target = sanitizeTargetUrl(data.url || "/")

  if (action === "view" || action === "open") {
    target = sanitizeTargetUrl(data.url || "/")
  } else if (action && data.actions?.[action]) {
    target = sanitizeTargetUrl(data.actions[action])
  }

  event.waitUntil(
    clients.matchAll({ type: "window", includeUncontrolled: true }).then(windows => {
      const open = windows.find(w => new URL(w.url).pathname === new URL(target, self.location.origin).pathname)
      return open ? open.focus() : clients.openWindow(target)
    })
  )
})
