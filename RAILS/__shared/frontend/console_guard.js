const errors = []
const remember = (type, message) => {
  const entry = { type, message: String(message || "").slice(0, 500), at: Date.now() }
  errors.push(entry)
  window.__pub4ConsoleErrors = errors
  window.dispatchEvent(new CustomEvent("pub4:console-error", { detail: entry }))
}

window.__pub4ConsoleErrors = errors
window.addEventListener("error", event => remember("error", event.message || event.error))
window.addEventListener("unhandledrejection", event => remember("unhandledrejection", event.reason))

export const consoleErrors = () => errors.slice()
