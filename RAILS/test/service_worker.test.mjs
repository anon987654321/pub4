import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import { registerHooks } from "node:module"
import { test } from "node:test"
import { pathToFileURL } from "node:url"

// The shared service worker's own event handlers, run in node. Workbox is
// replaced by recorders (the strategies and routes are Workbox's to test); what
// is measured is what this worker does with an event.
const stubs = {
  "workbox-background-sync": "export class BackgroundSyncPlugin {}",
  "workbox-cacheable-response": "export class CacheableResponsePlugin {}",
  "workbox-core": "export const clientsClaim = () => {}; export const setCacheNameDetails = () => {}",
  "workbox-expiration": "export class ExpirationPlugin {}",
  "workbox-precaching": [
    "export const cleanupOutdatedCaches = () => {}",
    "export const precacheAndRoute = (entries) => { globalThis.precached = entries }",
  ].join("\n"),
  "workbox-routing": [
    "export const registerRoute = () => {}",
    "export const setCatchHandler = (handler) => { globalThis.catchHandler = handler }",
  ].join("\n"),
  "workbox-strategies": [ "NetworkFirst", "NetworkOnly", "StaleWhileRevalidate", "CacheFirst" ]
    .map((name) => `export class ${name} { handle() { return globalThis.strategyHandle() } }`).join("\n"),
}
const stubUrl = (name) => `data:text/javascript,${encodeURIComponent(stubs[name])}`

registerHooks({
  resolve(specifier, context, next) {
    if (stubs[specifier]) return { url: stubUrl(specifier), shortCircuit: true }
    return next(specifier, context)
  },
})

const listeners = new Map()
const cached = new Map()
const shell = []
const opened = []
const shown = []
let preloadEnabled = false


globalThis.__APP_NAME__ = "brgen"
globalThis.self = globalThis
self.__WB_MANIFEST = []
self.location = new URL("https://brgen.no/")
self.skipWaiting = () => {}
self.addEventListener = (type, handler) => listeners.set(type, handler)
self.registration = {
  navigationPreload: { enable: async () => { preloadEnabled = true } },
  showNotification: async (title, options) => { shown.push({ title, options }) },
}
globalThis.caches = {
  match: async (key) => cached.get(typeof key === "string" ? key : new URL(key.url).pathname),
  open: async () => ({ addAll: async (urls) => shell.push(...urls) }),
  keys: async () => [],
  delete: async () => true,
}
globalThis.clients = {
  matchAll: async () => [],
  openWindow: async (url) => opened.push(url),
}

const source = new URL("../__shared/pwa/service_worker.js", import.meta.url)
await import(pathToFileURL(source.pathname).href)

const extendable = (extra = {}) => {
  const waits = []
  return { ...extra, waitUntil: (promise) => waits.push(promise), settle: () => Promise.all(waits) }
}

test("activate turns navigation preload on", async () => {
  const event = extendable()
  listeners.get("activate")(event)
  await event.settle()
  assert.equal(preloadEnabled, true)
})

test("activate deletes runtime caches left by earlier deploys and keeps everything else", async () => {
  const deleted = []
  const keys = caches.keys
  const del = caches.delete
  caches.keys = async () => [
    "brgen-pages-v1",
    "brgen-dynamic-v1",
    "brgen-assets-v1",
    "brgen-pages-__CACHE_VERSION__",
    "brgen-offline-forms",
    "workbox-precache-v2-somehash",
  ]
  caches.delete = async name => {
    deleted.push(name)
    return true
  }

  const event = extendable()
  listeners.get("activate")(event)
  await event.settle()

  caches.keys = keys
  caches.delete = del
  assert.deepEqual(
    deleted.sort(),
    [ "brgen-assets-v1", "brgen-dynamic-v1", "brgen-pages-v1" ],
    "the current version's caches, the forms queue and the precache survive",
  )
})

test("a failed navigation falls back to the page or /offline, never the cached home page", async () => {
  cached.set("/", new Response("someone's signed-in home"))
  cached.set("/offline", new Response("offline"))
  globalThis.strategyHandle = async () => { throw new Error("network down") }

  const response = await catchHandler({ event: {}, request: { mode: "navigate", url: "https://brgen.no/posts/7" } })

  assert.equal(await response.text(), "offline")
})

test("install keeps /offline and not the home page", async () => {
  const event = extendable()
  listeners.get("install")(event)
  await event.settle()
  assert.deepEqual(shell, [ "/offline" ])
})

test("a notification action opens its own address", async () => {
  const push = extendable({
    data: {
      json: () => ({
        title: "Ny melding",
        url: "/notifications",
        actions: [ { action: "reply", title: "Svar", url: "/conversations/3" } ],
      }),
    },
  })
  listeners.get("push")(push)
  await push.settle()

  const { options } = shown.at(-1)
  const reply = { action: "reply", title: "Svar", icon: undefined }
  assert.deepEqual(options.actions, [ reply ], "showNotification takes no url")
  assert.equal(options.data.actions.reply, "/conversations/3")

  const click = extendable({ action: "reply", notification: { data: options.data, close() {} } })
  listeners.get("notificationclick")(click)
  await click.settle()
  assert.deepEqual(opened, [ "/conversations/3" ])
})

test("the dynamic-route matcher is indented with the function it belongs to", () => {
  const text = readFileSync(source, "utf8")
  assert.doesNotMatch(text, /^const (path|isDynamicPath) =/m)
  assert.doesNotMatch(text, /^if \(/m)
})
