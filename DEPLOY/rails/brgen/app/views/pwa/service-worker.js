const CACHE = "brgen-v2"
const PERIODIC_FEED = "feed-prewarm"
const PERIODIC_BADGE = "badge-refresh"
const DB_NAME = "brgen-draft-store"
const QUEUE = "queue"

const openDb = () => new Promise((resolve, reject) => {
  const request = indexedDB.open(DB_NAME, 1)
  request.onupgradeneeded = () => {
    const db = request.result
    if (!db.objectStoreNames.contains(QUEUE)) db.createObjectStore(QUEUE)
  }
  request.onsuccess = () => resolve(request.result)
  request.onerror = () => reject(request.error)
})

const readQueue = async () => {
  const db = await openDb()
  const keys = await new Promise((resolve, reject) => {
    const request = db.transaction(QUEUE, "readonly").objectStore(QUEUE).getAllKeys()
    request.onsuccess = () => resolve(request.result || [])
    request.onerror = () => reject(request.error)
  })
  const entries = {}
  for (const key of keys) {
    entries[key] = await new Promise((resolve, reject) => {
      const request = db.transaction(QUEUE, "readonly").objectStore(QUEUE).get(key)
      request.onsuccess = () => resolve(request.result || [])
      request.onerror = () => reject(request.error)
    })
  }
  db.close()
  return entries
}

const writeQueue = async (key, value) => {
  const db = await openDb()
  await new Promise((resolve, reject) => {
    const request = db.transaction(QUEUE, "readwrite").objectStore(QUEUE).put(value, key)
    request.onsuccess = () => resolve(request.result)
    request.onerror = () => reject(request.error)
  })
  db.close()
}

const clearQueue = async key => {
  const db = await openDb()
  await new Promise((resolve, reject) => {
    const request = db.transaction(QUEUE, "readwrite").objectStore(QUEUE).delete(key)
    request.onsuccess = () => resolve()
    request.onerror = () => reject(request.error)
  })
  db.close()
}

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

self.addEventListener("sync", e => {
  if (e.tag !== "draft-store") return
  e.waitUntil((async () => {
    const queues = await readQueue()
    for (const [key, entries] of Object.entries(queues)) {
      const remaining = []
      for (const entry of entries) {
        try {
          await fetch(entry.action, {
            method: entry.method.toUpperCase(),
            credentials: "same-origin",
            headers: {
              "Content-Type": "application/x-www-form-urlencoded;charset=UTF-8",
              "X-CSRF-Token": entry.csrfToken || ""
            },
            body: new URLSearchParams(entry.payload)
          })
        } catch (_error) {
          remaining.push(entry)
        }
      }

      if (remaining.length) await writeQueue(key, remaining)
      else await clearQueue(key)
    }
  })())
})

self.addEventListener("periodicsync", e => {
  if (e.tag === PERIODIC_FEED) {
    e.waitUntil(caches.open(CACHE).then(c => c.addAll(["/"])))
    return
  }

  if (e.tag === PERIODIC_BADGE) {
    e.waitUntil(fetch("/notifications/badge").then(res => res.json()).then(data => {
      self.registration.setAppBadge?.(data.unread_count || 0)
    }).catch(() => {}))
  }
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
