const CACHE = "brgen-v2"

self.addEventListener("install", e => {
  e.waitUntil(caches.open(CACHE).then(c => c.addAll(["/"])))
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
    return
  } else if (isNav) {
    e.respondWith(fetch(e.request).catch(() => caches.match("/offline")))
    return
  }
  e.respondWith(caches.match(e.request).then(cached => cached || fetch(e.request)))
})

self.addEventListener("push", e => {
  const data = e.data?.json() ?? {}
  const title = data.title || "Brgen"
  e.waitUntil(
    self.registration.showNotification(title, {
      body:  data.body  || "",
      icon:  "/icon.png",
      badge: "/icon.png",
      data:  { url: data.url || "/" },
      vibrate: [80, 40, 80]
    }).then(() => self.registration.getNotifications())
      .then(notes => navigator.setAppBadge?.(notes.length))
  )
})

self.addEventListener("notificationclick", e => {
  e.notification.close()
  e.waitUntil(
    self.registration.getNotifications().then(notes => navigator.setAppBadge?.(notes.length)).then(() =>
      clients.matchAll({ type: "window", includeUncontrolled: true }).then(wins => {
        const url = e.notification.data?.url || "/"
        const match = wins.find(w => w.url.includes(url))
        return match ? match.focus() : clients.openWindow(url)
      })
    )
  )
})
