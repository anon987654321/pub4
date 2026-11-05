// enqueueSync() for a POST made while the network is down (the dating swipe).
// It writes into pwa_runtime's IndexedDB queue, the one offline queue, which
// replays in order on the next "online" event with a fresh CSRF token. This
// module kept a second, localStorage queue of its own until shared-031; the
// runtime folds whatever a device still holds there into its own on install.
import { enqueueRecord } from "pub4/pwa_runtime"

export async function enqueueSync({ url, method = "POST", body = {} }) {
  const entries = Object.entries(body || {}).map(([name, value]) => ({ name, kind: "text", value: String(value) }))
  try {
    return await enqueueRecord({ url, method, entries })
  } catch (error) {
    // No IndexedDB (a private window in an old browser): the write is lost, as
    // a full localStorage dropped it before.
    console.warn("pub4 offline queue:", error)
    return null
  }
}
