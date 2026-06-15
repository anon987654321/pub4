import { get, set, del, keys, update } from "idb-keyval"

const FEED_PREFIX = "feed:"
const DRAFT_PREFIX = "draft:"
const QUEUE_KEY = "sync-queue"
const VISIT_KEY = "pwa-visits"
const INSTALL_DISMISSED_KEY = "pwa-install-dismissed"

export async function cacheFeedItem(key, item, limit = 20) {
  const storeKey = `${FEED_PREFIX}${key}`
  await update(storeKey, (list = []) => {
    const next = [{ ...item, cachedAt: Date.now() }, ...list.filter(i => i.url !== item.url)]
    return next.slice(0, limit)
  })
}

export async function getFeedItems(key) {
  return (await get(`${FEED_PREFIX}${key}`)) || []
}

export async function saveDraft(key, payload) {
  await set(`${DRAFT_PREFIX}${key}`, { ...payload, savedAt: Date.now() })
}

export async function loadDraft(key) {
  return get(`${DRAFT_PREFIX}${key}`)
}

export async function clearDraft(key) {
  await del(`${DRAFT_PREFIX}${key}`)
}

export async function enqueueSync(item) {
  await update(QUEUE_KEY, (queue = []) => [...queue, { ...item, id: crypto.randomUUID(), queuedAt: Date.now() }])
}

export async function dequeueSync(id) {
  await update(QUEUE_KEY, (queue = []) => queue.filter(item => item.id !== id))
}

export async function listSyncQueue() {
  return (await get(QUEUE_KEY)) || []
}

export async function incrementVisitCount() {
  const count = Number(await get(VISIT_KEY) || 0) + 1
  await set(VISIT_KEY, count)
  return count
}

export async function visitCount() {
  return Number(await get(VISIT_KEY) || 0)
}

export async function installDismissed() {
  return Boolean(await get(INSTALL_DISMISSED_KEY))
}

export async function dismissInstall() {
  await set(INSTALL_DISMISSED_KEY, true)
}

export async function listDraftKeys() {
  const all = await keys()
  return all.filter(k => String(k).startsWith(DRAFT_PREFIX))
}