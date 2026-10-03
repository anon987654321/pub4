import { consentDecided } from "pub4/cookie_consent"

const SESSIONS_KEY = "pub4:onboarding:sessions"
const LAST_SEEN_KEY = "pub4:onboarding:last-seen"
const SESSION_GAP_MS = 30 * 60 * 1000

const MIN_SESSIONS = {
  welcome: 1,
  install: 1,
  menu_coach: 2,
  push: 3,
}

const WELCOME_PENDING = "welcomePending"

function read(key, fallback = 0) {
  try {
    const raw = window.localStorage.getItem(key)
    return raw === null ? fallback : Number(raw)
  } catch (_) {
    return fallback
  }
}

function write(key, value) {
  try { window.localStorage.setItem(key, String(value)) } catch (_) {}
}

function consentRequired() {
  return document.body?.dataset.cookieConsentRequired === "true"
}

export function noteSession() {
  if (consentRequired() && !consentDecided()) return sessions()

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

export function installVisible() {
  const el = document.getElementById("install-prompt")
  return !!el && !el.hidden
}

export function welcomePending() {
  return document.documentElement.dataset[WELCOME_PENDING] === "true"
}

export function setWelcomePending(value) {
  document.documentElement.dataset[WELCOME_PENDING] = value ? "true" : "false"
}

export function mayPrompt(kind) {
  if (consentRequired() && !consentDecided()) return false

  const floor = MIN_SESSIONS[kind]
  if (floor === undefined) return true
  if (sessions() < floor) return false

  if (kind !== "welcome" && welcomePending()) return false
  return kind === "install" || !installVisible()
}

export const YIELD_EVENT = "pub4:onboarding-yield"

export function announceInstallVisible() {
  window.dispatchEvent(new CustomEvent(YIELD_EVENT, { detail: { to: "install" } }))
}