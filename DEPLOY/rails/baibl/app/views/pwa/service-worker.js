const CACHE   = "baibl-v2"
const OFFLINE = "/offline"

self.addEventListener("install", e => {
  e.waitUntil(caches.open(CACHE).then(c => c.addAll(["/", OFFLINE])))
  self.skipWaiting()
})

self.addEventListener("activate", e => {
  e.waitUntil(caches.keys().then(keys =>
    Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k)))
  ))
  self.clients.claim()
})

self.addEventListener("fetch", e => {
  if (e.request.method !== "GET") return
  const url = new URL(e.request.url)
  const isNav = e.request.mode === "navigate"
  const isAsset = /\.(js|css|png|jpg|jpeg|webp|svg|woff2?|ico)$/.test(url.pathname)
  if (isAsset) {
    e.respondWith(caches.match(e.request).then(cached => cached || fetch(e.request).then(res => {
      const clone = res.clone()
      caches.open(CACHE).then(c => c.put(e.request, clone))
      return res
    })))
  } else if (isNav) {
    e.respondWith(fetch(e.request).catch(() => caches.match(OFFLINE)))
  }
})
