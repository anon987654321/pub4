const CACHE_VERSION = "__CACHE_VERSION__"
const CACHE   = `blognet-${CACHE_VERSION}`
const OFFLINE = "/offline"
const PERIODIC_TAG = "feed-prewarm"
const PERIODIC_BADGE = "badge-refresh"
const DB_NAME = "blognet-draft-store"
const QUEUE = "queue"
const OFFLINE_FORMS = "offline-forms"

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

const requestEntry = async request => ({
  action: request.url,
  method: request.method,
  headers: Object.fromEntries(request.headers.entries()),
  body: await request.clone().text()
})

const queueRequest = async request => {
  const queues = await readQueue()
  const entries = queues[OFFLINE_FORMS] || []
  entries.push(await requestEntry(request))
  await writeQueue(OFFLINE_FORMS, entries)
}

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
  if (e.request.method !== "GET") {
    const request = e.request.clone()
    e.respondWith(fetch(e.request).catch(async () => {
      await queueRequest(request)
      await self.registration.sync?.register(OFFLINE_FORMS).catch(() => {})
      return new Response("", { status: 202, statusText: "Queued offline" })
    }))
    return
  }
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

self.addEventListener("sync", e => {
  if (e.tag !== "draft-store" && e.tag !== OFFLINE_FORMS) return
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
  if (e.tag === PERIODIC_TAG) {
    e.waitUntil(caches.open(CACHE).then(c => c.addAll(["/"])))
    return
  }

  if (e.tag === PERIODIC_BADGE) {
    e.waitUntil(fetch("/notifications/badge").then(res => res.json()).then(data => {
      self.registration.setAppBadge?.(data.unread_count || 0)
    }).catch(() => {}))
  }
})
