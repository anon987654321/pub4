export const COOKIE_NAME = "pub4_consent"
export const COOKIE_VERSION = "v1"
export const PURPOSES = [ "analytics", "advertising" ]

export function readConsent() {
  const raw = document.cookie
    .split(";")
    .map((part) => part.trim())
    .find((part) => part.startsWith(COOKIE_NAME + "="))
    ?.slice(COOKIE_NAME.length + 1)

  if (!raw) return null

  let decoded
  try {
    decoded = decodeURIComponent(raw)
  } catch (_) {
    return null
  }

  const [version, recordedAt, purposeString = ""] = decoded.split("|", 3)
  if (version !== COOKIE_VERSION || !recordedAt) return null

  return {
    version,
    recordedAt,
    purposes: purposeString.split(",").filter((purpose) => PURPOSES.includes(purpose))
  }
}

export function consentDecided() {
  return readConsent() !== null
}

export function allows(purpose) {
  return readConsent()?.purposes.includes(purpose) === true
}

export function saveConsent(purposes) {
  const selected = PURPOSES.filter((purpose) => purposes.includes(purpose))
  const recordedAt = new Date().toISOString()
  const payload = [ COOKIE_VERSION, recordedAt, selected.join(",") ].join("|")
  const secure = window.location.protocol === "https:" ? "; Secure" : ""

  document.cookie =
    COOKIE_NAME + "=" + encodeURIComponent(payload) +
    "; Max-Age=31536000; Path=/; SameSite=Lax" + secure

  const detail = { version: COOKIE_VERSION, recordedAt, purposes: selected }
  window.dispatchEvent(new CustomEvent("pub4:cookie-consent-resolved", { detail }))
  return detail
}