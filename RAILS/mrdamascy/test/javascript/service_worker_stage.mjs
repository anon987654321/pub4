// Stand-ins for the service worker's world: its event hooks, an in-memory
// Cache Storage and a network that can be switched off. `navigate(path)`
// answers one page navigation and resolves to the body it was served.
const handlers = {}
const store = new Map()
const network = { online: true }

globalThis.self = {
  location: { origin: "https://mrdamascy.test" },
  addEventListener: (name, handler) => { handlers[name] = handler },
  skipWaiting: () => Promise.resolve(),
  clients: { claim: () => Promise.resolve() },
}

const page = (body) => ({ ok: true, body, clone: () => page(body), text: () => Promise.resolve(body) })
const keyOf = (request) => (typeof request === "string" ? request : new URL(request.url).pathname)

globalThis.caches = {
  open: () => Promise.resolve({
    put: (request, response) => { store.set(keyOf(request), response) },
    addAll: (urls) => { urls.forEach((url) => store.set(url, page(`cached ${url}`))) },
  }),
  match: (request) => Promise.resolve(store.get(keyOf(request))),
  keys: () => Promise.resolve([]),
}

globalThis.fetch = (request) =>
  network.online ? Promise.resolve(page(`live ${keyOf(request)}`)) : Promise.reject(new Error("offline"))

const later = globalThis.setTimeout
const tick = () => new Promise((resolve) => later(resolve, 0))

const navigate = async (path) => {
  let answer
  const request = { method: "GET", mode: "navigate", url: `https://mrdamascy.test${path}` }
  handlers.fetch({ request, respondWith: (promise) => { answer = promise } })
  const response = await answer
  await tick()
  return response ? response.body : null
}
