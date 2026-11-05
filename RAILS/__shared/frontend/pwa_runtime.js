// The one offline write queue. A form marked data-pwa-offline that is submitted
// with no network, and every enqueueSync() call (pwa_offline_store.js, used by
// the dating swipe), is stored in IndexedDB and replayed in order when the
// browser comes back online. The localStorage queue that pwa_offline_store.js
// kept beside this one is folded in on install.
const DB_NAME = "pub4-pwa"
const DB_VERSION = 1
const STORE = "mutations"
const EVENT = "pub4:pwa-queue"
const MAX_QUEUE_SIZE = 100
const LEGACY_STORAGE_KEY = "pub4:offline-sync-queue"

const canUseIndexedDB = () => typeof indexedDB !== "undefined"

const openDb = () => new Promise((resolve, reject) => {
  if (!canUseIndexedDB()) {
    reject(new Error("IndexedDB unavailable"))
    return
  }
  const request = indexedDB.open(DB_NAME, DB_VERSION)
  request.onupgradeneeded = () => request.result.createObjectStore(STORE, { keyPath: "id" })
  request.onsuccess = () => resolve(request.result)
  request.onerror = () => reject(request.error)
})

const settle = (request) => new Promise((resolve, reject) => {
  request.onsuccess = () => resolve(request.result)
  request.onerror = () => reject(request.error)
})

const withStore = async (mode, work) => {
  const db = await openDb()
  try {
    const tx = db.transaction(STORE, mode)
    const store = tx.objectStore(STORE)
    const value = await work(store)
    await new Promise((resolve, reject) => {
      tx.oncomplete = resolve
      tx.onerror = () => reject(tx.error)
      tx.onabort = () => reject(tx.error || new Error("transaction aborted"))
    })
    return value
  } finally {
    db.close()
  }
}

const notify = (type, detail = {}) => window.dispatchEvent(new CustomEvent(EVENT, { detail: { type, ...detail } }))

const serializeFormData = (formData) => Array.from(formData.entries()).map(([name, value]) => (
  value instanceof File
    ? { name, kind: "file", blob: value, name_on_disk: value.name, type: value.type, last_modified: value.lastModified }
    : { name, kind: "text", value: String(value) }
))

const deserializeFormData = (entries) => {
  const formData = new FormData()
  entries.forEach((entry) => (
    entry.kind === "file" ? formData.append(entry.name, entry.blob, entry.name_on_disk) : formData.append(entry.name, entry.value)
  ))
  return formData
}

// A queued write may only go back to the origin that queued it.
const sameOriginUrl = (value) => {
  const raw = String(value ?? "").trim()
  if (!raw) return null
  try {
    const url = new URL(raw, window.location.origin)
    return url.origin === window.location.origin ? url.href : null
  } catch (_error) {
    return null
  }
}

const allRecords = () => withStore("readonly", (store) => settle(store.getAll()))
  .then((records) => records.sort((a, b) => a.created_at - b.created_at))

const removeRecord = (id) => withStore("readwrite", (store) => settle(store.delete(id)))

export const queueSize = async () => withStore("readonly", (store) => settle(store.count()))

// Stores one write and keeps only the newest MAX_QUEUE_SIZE, so a device that
// stays offline for days cannot grow the queue without bound.
export const enqueueRecord = async ({ url, method = "POST", entries = [] }) => {
  const id = crypto.randomUUID()
  const record = { id, created_at: Date.now(), url: new URL(url, location.href).toString(), method: method.toUpperCase(), entries }
  await withStore("readwrite", (store) => settle(store.put(record)))
  const records = await allRecords()
  for (const stale of records.slice(0, Math.max(0, records.length - MAX_QUEUE_SIZE))) await removeRecord(stale.id)
  notify("queued", { id, count: await queueSize() })
  return id
}

export const enqueueForm = async (form) => enqueueRecord({
  url: form.action,
  method: form.method || "POST",
  entries: serializeFormData(new FormData(form)),
})

// The token a queued form carries is the one its page was rendered with. By the
// time the queue replays, the session may have rotated (a sign-in, an expired
// cookie), and Rails answers that token with a 422. The token is read fresh from
// a page fetched now, and the document's own meta tag is the fallback.
export const freshCsrfToken = async () => {
  try {
    const response = await fetch(new URL("/", window.location.origin).href, { credentials: "include", headers: { Accept: "text/html" } })
    const token = (await response.text()).match(/<meta name="csrf-token" content="([^"]*)"/)?.[1]
    if (token) return token
  } catch (_error) {
    // Offline again, or the page did not answer: fall back to this document's.
  }
  return document.querySelector('meta[name="csrf-token"]')?.content || ""
}

const send = (record, url, token) => {
  const body = deserializeFormData(record.entries)
  if (body.has("authenticity_token")) body.set("authenticity_token", token)
  return fetch(url, {
    method: record.method,
    body,
    credentials: "include",
    redirect: "follow",
    headers: {
      Accept: "text/vnd.turbo-stream.html, text/html",
      "X-CSRF-Token": token,
      "X-Idempotency-Key": record.id,
      "X-Pub4-Offline-Replay": "1",
    },
  })
}

// Replays in order. A record the server accepts (or already has: 409) leaves the
// queue. A 422 after a fresh token is the server refusing the write itself, so
// it leaves too, reported as rejected, rather than blocking every write behind
// it for good. Any other failure stops the replay and keeps the record.
export const replay = async () => {
  if (!navigator.onLine || !canUseIndexedDB()) return
  const records = await allRecords()
  if (records.length === 0) return

  let token = await freshCsrfToken()
  for (const record of records) {
    const url = sameOriginUrl(record.url)
    if (!url) {
      await removeRecord(record.id)
      notify("rejected", { id: record.id, status: 0 })
      continue
    }
    try {
      let response = await send(record, url, token)
      if (response.status === 422) {
        token = await freshCsrfToken()
        response = await send(record, url, token)
      }
      if (response.ok || response.status === 409) {
        await removeRecord(record.id)
        notify("replayed", { id: record.id })
      } else if (response.status === 422) {
        await removeRecord(record.id)
        notify("rejected", { id: record.id, status: response.status })
      } else {
        notify("blocked", { id: record.id, status: response.status })
        break
      }
    } catch (error) {
      notify("offline", { id: record.id, error: String(error) })
      break
    }
  }
  notify("drained", { count: await queueSize() })
}

// Entries the retired localStorage queue still holds on a device move into this
// one, once.
const adoptLegacyQueue = async () => {
  let legacy = []
  try {
    legacy = JSON.parse(localStorage.getItem(LEGACY_STORAGE_KEY) || "[]")
    localStorage.removeItem(LEGACY_STORAGE_KEY)
  } catch (_error) {
    return
  }
  for (const entry of legacy) {
    if (!sameOriginUrl(entry.url)) continue
    const entries = Object.entries(entry.body || {}).map(([name, value]) => ({ name, kind: "text", value: String(value) }))
    await enqueueRecord({ url: entry.url, method: entry.method || "POST", entries })
  }
}

export const requestStoragePersistence = async () => (navigator.storage?.persist ? await navigator.storage.persist() : false)

export const installOfflineQueue = () => {
  if (window.__pub4OfflineQueueInstalled || !canUseIndexedDB()) return
  window.__pub4OfflineQueueInstalled = true
  requestStoragePersistence().catch(() => {})
  window.addEventListener("online", replay)
  window.addEventListener("pub4:pwa-replay", replay)
  document.addEventListener("submit", async (event) => {
    const form = event.target
    if (!(form instanceof HTMLFormElement) || !form.matches("form[data-pwa-offline]")) return
    if (navigator.onLine) return
    event.preventDefault()
    try {
      await enqueueForm(form)
      // The words are the form's own, in the page's language (data-pwa-queued-text);
      // a form that names none shows none rather than a Norwegian default.
      const status = form.querySelector("[data-pwa-queue-status]")
      if (status && form.dataset.pwaQueuedText) status.textContent = form.dataset.pwaQueuedText
    } catch (error) {
      console.error("pub4 offline queue:", error)
    }
  })
  adoptLegacyQueue()
    .then(replay)
    .catch((error) => console.warn("pub4 offline queue replay:", error))
}

export const pwaCapabilities = () => ({
  share_target: true,
  media_session: typeof navigator !== "undefined" && Boolean(navigator.mediaSession),
  app_shortcuts: true,
  launch_handler: "launchQueue" in window,
  web_share_level_2: "canShare" in navigator,
  indexeddb: canUseIndexedDB(),
  opfs: Boolean(navigator.storage?.getDirectory),
  periodic_background_sync: "serviceWorker" in navigator && "periodicSync" in ServiceWorkerRegistration.prototype,
  barcode_detector: "BarcodeDetector" in window,
  wake_lock: "wakeLock" in navigator,
  fullscreen: Boolean(document.documentElement.requestFullscreen),
  geolocation: "geolocation" in navigator,
  document_picture_in_picture: "documentPictureInPicture" in window,
})
