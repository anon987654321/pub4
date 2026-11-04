// A stand-in document, window and timers that record what the track
// controller asks for; `track(state, hidden)` connects one controller.
const later = globalThis.setTimeout
const tick = () => new Promise((resolve) => later(resolve, 0))
const seen = { intervals: 0, visits: [], reloads: 0, fetched: [] }
const listeners = {}

globalThis.setInterval = () => ++seen.intervals
globalThis.clearInterval = () => {}

globalThis.document = {
  hidden: false,
  addEventListener: (name, callback) => { listeners[name] = callback },
  removeEventListener: () => {},
}

globalThis.window = {
  location: { href: "https://mrdamascy.test/track/abc", reload: () => seen.reloads++ },
  Turbo: { visit: (url, options) => seen.visits.push([url, options.action]) },
}

globalThis.fetch = (url) => {
  seen.fetched.push(url)
  return Promise.resolve({ ok: true, json: () => Promise.resolve({ state: "ready", eta: 5 }) })
}

const track = (state, hidden = false) => {
  document.hidden = hidden
  const controller = new Subject({})
  Object.assign(controller, { urlValue: "/mat/track/abc/status", stateValue: state, intervalValue: 10_000 })
  controller.connect()
  return controller
}
