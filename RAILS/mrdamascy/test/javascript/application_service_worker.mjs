// application.js with its imports dropped: Turbo visits fire turbo:load
// again, and the service worker must be registered once.
const registered = []
const listeners = {}
const serviceWorker = { register: (url) => { registered.push(url); return Promise.resolve() } }
Object.defineProperty(globalThis, "navigator", { value: { serviceWorker }, configurable: true })
globalThis.window = { addEventListener: (name, handler) => { (listeners[name] ||= []).push(handler) } }
