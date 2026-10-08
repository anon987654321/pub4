import assert from "node:assert/strict"
import { test } from "node:test"
import { pathToFileURL } from "node:url"

const listeners = new Map()
const store = new Map()
const requests = []

globalThis.localStorage = {
  getItem: (key) => (store.has(key) ? store.get(key) : null),
  setItem: (key, value) => store.set(key, String(value)),
}

globalThis.document = {
  querySelector: (selector) =>
    selector === 'meta[name="csrf-token"]' ? { content: "csrf-contract" } : null,
}

globalThis.navigator = { onLine: false }
globalThis.window = {
  location: new URL("https://brgen.no/offline"),
  addEventListener: (type, handler) => listeners.set(type, handler),
}

globalThis.fetch = async (url, options) => {
  requests.push({ url, options })
  return { ok: true, status: 200 }
}

const modulePath = pathToFileURL(
  new URL("../__shared/frontend/pwa_offline_store.js", import.meta.url).pathname,
).href
const { enqueueSync } = await import(modulePath)

const STORAGE_KEY = "pub4:offline-sync-queue"

test("offline queue keeps only its newest 100 entries", async () => {
  store.clear()

  for (let id = 0; id < 105; id += 1) {
    await enqueueSync({ id, url: "/posts/" + id, body: { id } })
  }

  const queue = JSON.parse(store.get(STORAGE_KEY))
  assert.equal(queue.length, 100)
  assert.equal(queue[0].id, 5)
  assert.equal(queue[queue.length - 1].id, 104)
})

test("online replay rejects cross-origin writes and preserves the CSRF header", async () => {
  store.clear()
  requests.length = 0

  await enqueueSync({ id: "external", url: "https://evil.example/steal", body: { a: "1" } })
  await enqueueSync({ id: "local", url: "/posts/42", method: "PATCH", body: { title: "Hei" } })

  await listeners.get("online")()

  assert.equal(requests.length, 1)
  assert.equal(requests[0].url, "https://brgen.no/posts/42")
  assert.equal(requests[0].options.method, "PATCH")
  assert.equal(requests[0].options.headers["X-CSRF-Token"], "csrf-contract")
  assert.match(requests[0].options.body.toString(), /title=Hei/)

  assert.equal(store.get(STORAGE_KEY), "[]")
})
