import assert from "node:assert/strict"
import { registerHooks } from "node:module"
import { test } from "node:test"
import { pathToFileURL } from "node:url"

// The one offline queue: pwa_runtime.js in IndexedDB, with pwa_offline_store.js
// writing into it. Node has no IndexedDB, so a small in-memory one stands in:
// every request settles on a microtask and a transaction completes on the next
// timer, after its work, as a browser's does.
const rows = new Map()
const settled = (work) => {
  const request = {}
  queueMicrotask(() => {
    try {
      request.result = work()
      request.onsuccess?.()
    } catch (error) {
      request.error = error
      request.onerror?.()
    }
  })
  return request
}

const objectStore = {
  put: (record) => settled(() => rows.set(record.id, record)),
  getAll: () => settled(() => [...rows.values()]),
  count: () => settled(() => rows.size),
  delete: (id) => settled(() => rows.delete(id)),
}

const database = {
  createObjectStore() {},
  close() {},
  transaction() {
    const tx = { objectStore: () => objectStore }
    setTimeout(() => tx.oncomplete?.(), 0)
    return tx
  },
}

globalThis.indexedDB = {
  open() {
    const request = {}
    queueMicrotask(() => {
      request.result = database
      request.onupgradeneeded?.()
      request.onsuccess?.()
    })
    return request
  },
}

const storage = new Map()
globalThis.localStorage = {
  getItem: (key) => (storage.has(key) ? storage.get(key) : null),
  setItem: (key, value) => storage.set(key, String(value)),
  removeItem: (key) => storage.delete(key),
}

const documentListeners = new Map()
globalThis.document = {
  querySelector: (selector) => (selector === 'meta[name="csrf-token"]' ? { content: "page-token" } : null),
  addEventListener: (type, handler) => documentListeners.set(type, handler),
  documentElement: {},
}
globalThis.HTMLFormElement = class {}

const events = []
const windowListeners = new Map()
globalThis.location = new URL("https://brgen.no/dating")
globalThis.window = {
  location: globalThis.location,
  addEventListener: (type, handler) => windowListeners.set(type, handler),
  dispatchEvent: (event) => events.push(event.detail),
}
Object.defineProperty(globalThis.navigator, "onLine", { value: true, configurable: true, writable: true })

const requests = []
let answer = () => ({ ok: true, status: 200 })
globalThis.fetch = async (url, options = {}) => {
  if (options.method === undefined) {
    return { ok: true, status: 200, text: async () => '<head><meta name="csrf-token" content="fresh-token"></head>' }
  }
  requests.push({ url, options })
  return answer(url, options)
}

const frontend = (name) => pathToFileURL(new URL(`../__shared/frontend/${name}`, import.meta.url).pathname).href
registerHooks({
  resolve(specifier, context, next) {
    if (specifier === "pub4/pwa_runtime") return { url: frontend("pwa_runtime.js"), shortCircuit: true }
    return next(specifier, context)
  },
})

const runtime = await import(frontend("pwa_runtime.js"))
const { enqueueSync } = await import(frontend("pwa_offline_store.js"))

const reset = () => {
  rows.clear()
  storage.clear()
  requests.length = 0
  events.length = 0
  answer = () => ({ ok: true, status: 200 })
}

test("enqueueSync writes into the IndexedDB queue and keeps only its newest 100", async () => {
  reset()
  for (let id = 0; id < 105; id += 1) await enqueueSync({ url: `/posts/${id}`, body: { id } })

  assert.equal(storage.size, 0, "no second, localStorage queue")
  const queued = [...rows.values()].sort((a, b) => a.created_at - b.created_at)
  assert.equal(queued.length, 100)
  assert.deepEqual(queued.map((record) => record.entries[0].value).slice(0, 1), ["5"])
  assert.equal(queued.at(-1).url, "https://brgen.no/posts/104")
})

test("replay sends same-origin writes with a fresh CSRF token and drops cross-origin ones", async () => {
  reset()
  await enqueueSync({ url: "https://evil.example/steal", body: { a: "1" } })
  await enqueueSync({ url: "/posts/42", method: "PATCH", body: { title: "Hei", authenticity_token: "stale" } })

  await runtime.replay()

  assert.equal(requests.length, 1)
  assert.equal(requests[0].url, "https://brgen.no/posts/42")
  assert.equal(requests[0].options.method, "PATCH")
  assert.equal(requests[0].options.headers["X-CSRF-Token"], "fresh-token")
  assert.equal(requests[0].options.body.get("authenticity_token"), "fresh-token")
  assert.equal(requests[0].options.body.get("title"), "Hei")
  assert.equal(rows.size, 0)
  assert.ok(events.some((event) => event.type === "rejected"))
})

test("a 422 does not block the queue behind it", async () => {
  reset()
  await enqueueSync({ url: "/dating/likes", body: { user_id: "1" } })
  await enqueueSync({ url: "/dating/likes", body: { user_id: "2" } })
  const refused = { ok: false, status: 422 }
  const accepted = { ok: true, status: 200 }
  answer = (_url, options) => (options.body.get("user_id") === "1" ? refused : accepted)

  await runtime.replay()

  const sent = requests.map(({ options }) => options.body.get("user_id"))
  assert.deepEqual(sent, ["1", "1", "2"], "the refused write is retried once with a new token, then the next one goes")
  assert.equal(rows.size, 0)
  assert.ok(events.some((event) => event.type === "rejected" && event.status === 422))
})

test("a server error stops the replay and keeps the write", async () => {
  reset()
  await enqueueSync({ url: "/dating/likes", body: { user_id: "1" } })
  answer = () => ({ ok: false, status: 503 })

  await runtime.replay()

  assert.equal(rows.size, 1)
  assert.ok(events.some((event) => event.type === "blocked" && event.status === 503))
})

test("install folds the retired localStorage queue in and words the status only from the form", async () => {
  reset()
  const legacy = [ { url: "/dating/passes", method: "POST", body: { user_id: "9" } } ]
  storage.set("pub4:offline-sync-queue", JSON.stringify(legacy))

  runtime.installOfflineQueue()
  await new Promise((resolve) => setTimeout(resolve, 20))

  assert.equal(storage.has("pub4:offline-sync-queue"), false)
  assert.equal(requests.at(-1).url, "https://brgen.no/dating/passes")

  globalThis.navigator.onLine = false
  const status = { textContent: "" }
  const form = Object.assign(new HTMLFormElement(), {
    action: "https://brgen.no/posts",
    method: "post",
    dataset: {},
    matches: () => true,
    querySelector: () => status,
  })
  globalThis.FormData = class extends FormData { constructor() { super() } }
  await documentListeners.get("submit")({ target: form, preventDefault() {} })
  assert.equal(status.textContent, "", "no Norwegian fallback when the form names no text")

  form.dataset.pwaQueuedText = "Saved for offline"
  await documentListeners.get("submit")({ target: form, preventDefault() {} })
  assert.equal(status.textContent, "Saved for offline")
  globalThis.navigator.onLine = true
})
