// Which onboarding prompt is allowed to speak, and when.
//
// Three prompts compete for a first-time visitor's attention and none of them
// knew the others existed:
//
//   install-prompt   "Install this app"            shared/_install_prompt
//   menu coach       "Menyen er nederst"           scroll_chrome_controller
//   push enable      "Slå på varsler"              push_controller
//
// The coach fired on a timer on the first page view and the push button
// appeared as soon as permission was `default`, so a visitor who had not yet
// read a single post could meet two interruptions before the product had shown
// them anything — while the install prompt, the one worth taking, waited
// for a post and so arrived last or not at all.
//
// The order is deliberate and not a matter of timing luck:
//
//   1. Install always outranks the other two. It is the only prompt that
//      improves every later visit, and it is the only one that becomes
//      impossible to offer once the visitor leaves. It appears when the
//      browser can install (beforeinstallprompt, or iOS instructions) —
//      not after a post. Waiting for value meant a first visit never saw it.
//   2. The other two are worth nothing to someone still deciding whether they
//      care. They wait until the app is familiar, and they wait behind install.
//
// Familiarity is counted in sessions rather than page views. A visitor who
// opens six pages in one sitting has not become more used to the app six times
// over; they have visited once. A gap of SESSION_GAP_MS ends a session.

const SESSIONS_KEY = "pub4:onboarding:sessions"
const LAST_SEEN_KEY = "pub4:onboarding:last-seen"
const SESSION_GAP_MS = 30 * 60 * 1000

// Sessions before each prompt may appear. Install is 1 because the first
// visit is the one that can still install.
const MIN_SESSIONS = {
  install: 1,
  menu_coach: 2,
  push: 3,
}

function read(key, fallback = 0) {
  try {
    const raw = window.localStorage.getItem(key)
    return raw === null ? fallback : Number(raw)
  } catch (_) {
    // Private mode throws on access, not just on write.
    return fallback
  }
}

function write(key, value) {
  try { window.localStorage.setItem(key, String(value)) } catch (_) {}
}

// Call once per page load. Increments only when the previous load was long
// enough ago to count as a separate sitting, so it is safe to call on every
// Turbo visit.
export function noteSession() {
  const now = Date.now()
  const last = read(LAST_SEEN_KEY, 0)
  const count = read(SESSIONS_KEY, 0)

  if (now - last > SESSION_GAP_MS) write(SESSIONS_KEY, count + 1)
  write(LAST_SEEN_KEY, now)
  return sessions()
}

export function sessions() {
  return Math.max(read(SESSIONS_KEY, 0), 1)
}

// True while the install prompt is on screen. Checked live rather than tracked,
// because the install prompt can reveal at any moment (the visitor posts, plays
// a track, sends a message) and a cached answer would let a lower-priority
// prompt open on top of it.
export function installVisible() {
  const el = document.getElementById("install-prompt")
  return !!el && !el.hidden
}

// The one question the callers ask. `kind` is a key of MIN_SESSIONS.
export function mayPrompt(kind) {
  const floor = MIN_SESSIONS[kind]
  if (floor === undefined) return true
  if (sessions() < floor) return false

  return kind === "install" || !installVisible()
}

// Install has just appeared — anything below it should get out of the way.
// install_prompt_controller fires this; the two lower prompts listen.
export const YIELD_EVENT = "pub4:onboarding-yield"

export function announceInstallVisible() {
  window.dispatchEvent(new CustomEvent(YIELD_EVENT, { detail: { to: "install" } }))
}
