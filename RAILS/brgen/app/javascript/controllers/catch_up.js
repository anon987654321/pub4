import { Turbo } from "@hotwired/turbo-rails"

// What a live page missed while its cable was down. Broadcasts sent while a
// phone slept or a tab was hidden are gone for good, so when the stream comes
// back (Turbo marks its <turbo-cable-stream-source> "connected" again) or the
// page is shown again, the page asks the server for everything newer than the
// newest record it holds and renders the answer as the stream would have.
//
// One place for both live pages: feed_updates_controller (posts, into the
// pending chip) and live_comments_controller (comments, into the thread).
export function watchForCatchUp(source, catchUp) {
  const onVisible = () => {
    if (document.visibilityState === "visible") catchUp()
  }
  const observer = new MutationObserver(() => {
    if (source?.hasAttribute("connected")) catchUp()
  })

  if (source) observer.observe(source, { attributes: true, attributeFilter: ["connected"] })
  document.addEventListener("visibilitychange", onVisible)

  return () => {
    observer.disconnect()
    document.removeEventListener("visibilitychange", onVisible)
  }
}

// The newest id among the records rendered as elements with ids like post_12
// inside root, or the floor the server rendered if that is higher.
export function newestId(root, prefix, floor = 0) {
  let newest = floor
  for (const element of root.querySelectorAll(`[id^="${prefix}_"]`)) {
    const id = Number.parseInt(element.id.slice(prefix.length + 1), 10)
    if (Number.isInteger(id) && id > newest) newest = id
  }
  return newest
}

export async function fetchMissed(url, after) {
  if (!url) return

  const request = new URL(url, window.location.href)
  request.searchParams.set("after", String(after))
  try {
    const response = await fetch(request, { headers: { Accept: "text/vnd.turbo-stream.html" } })
    if (response.ok) Turbo.renderStreamMessage(await response.text())
  } catch {
    // Still offline: the next reconnect asks again.
  }
}
