// Minimal offline sync queue for POST actions issued while the network is
// unavailable (e.g. dating_swipe_controller). Queues to localStorage and
// replays on the next "online" event; each entry is retried once per event
// and dropped from the queue whether it succeeds or fails (avoids an
// infinite retry loop wedging the queue on a permanently-failing request).
const STORAGE_KEY = "pub4:offline-sync-queue"

function readQueue() {
  try {
    return JSON.parse(localStorage.getItem(STORAGE_KEY) || "[]")
  } catch (_) {
    return []
  }
}

function writeQueue(queue) {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(queue))
  } catch (_) {
    // storage full or unavailable (private mode) -- drop silently
  }
}

export async function enqueueSync(entry) {
  const queue = readQueue()
  queue.push({ ...entry, queuedAt: Date.now() })
  writeQueue(queue)
}

async function flushQueue() {
  const queue = readQueue()
  if (!queue.length) return
  writeQueue([])

  const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content || ""
  await Promise.allSettled(
    queue.map((entry) =>
      fetch(entry.url, {
        method: entry.method || "POST",
        headers: {
          "Content-Type": "application/x-www-form-urlencoded",
          "X-CSRF-Token": csrfToken,
          "Accept": "text/vnd.turbo-stream.html, text/html"
        },
        body: entry.body ? new URLSearchParams(entry.body) : undefined
      })
    )
  )
}

if (typeof window !== "undefined") {
  window.addEventListener("online", flushQueue)
  if (navigator.onLine) flushQueue()
}
