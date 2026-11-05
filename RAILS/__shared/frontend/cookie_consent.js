export const COOKIE_NAME = "pub4_consent"
export const COOKIE_VERSION = "v1"
export const PURPOSES = [ "analytics", "advertising" ]

export function readConsent() {
  const raw = document.cookie
    .split(";")
    .map((part) => part.trim())
    .find((part) => part.startsWith(`${COOKIE_NAME}=`))
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

// The registrable domain, read the way the session cookie's `domain: :all` is
// (session_store.rb): the host's last two labels, so a choice made on brgen.no
// also holds on markedsplass.brgen.no and never reaches lsangeles.com. A bare
// host (localhost) or an IP address keeps a host-only cookie, as Rails does.
export function consentCookieDomain(hostname = window.location.hostname) {
  const labels = hostname.split(".")
  if (labels.length < 2 || labels.includes("") || /^[\d.]+$/.test(hostname) || hostname.includes(":")) return null
  return labels.slice(-2).join(".")
}

export function saveConsent(purposes) {
  const selected = PURPOSES.filter((purpose) => purposes.includes(purpose))
  const recordedAt = new Date().toISOString()
  const payload = [ COOKIE_VERSION, recordedAt, selected.join(",") ].join("|")
  const secure = window.location.protocol === "https:" ? "; Secure" : ""
  const domain = consentCookieDomain()
  const scope = domain ? `; Domain=${domain}` : ""
  // A choice saved before the cookie named its domain is host-only; expire it,
  // or the browser would keep sending the old one ahead of the new.
  if (domain) document.cookie = `${COOKIE_NAME}=; Max-Age=0; Path=/`

  document.cookie =
    COOKIE_NAME + "=" + encodeURIComponent(payload) +
    `; Max-Age=31536000; Path=/${scope}; SameSite=Lax${secure}`

  const detail = { version: COOKIE_VERSION, recordedAt, purposes: selected }
  window.dispatchEvent(new CustomEvent("pub4:cookie-consent-resolved", { detail }))
  return detail
}
