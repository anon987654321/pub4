const DB_NAME = `${typeof location !== "undefined" ? location.hostname : "app"}-idb-keyval`

const ensureStore = (request, storeName) => {
  request.onupgradeneeded = () => {
    const db = request.result
    if (!db.objectStoreNames.contains(storeName)) db.createObjectStore(storeName)
  }
}

// One database holds every store (the draft store keeps a draft and a queue). A store is
// created only in an upgrade, so a database that already exists without the one asked for is
// reopened a version higher to add it: pinned at version 1, the second store a page asked for
// threw "One of the specified object stores was not found" on every composer.

// Two calls can race (the draft store clears its draft and queue together): both find a store
// missing and both ask for the next version, and the second, finding it already there, gets no
// upgrade. So every open checks again, a few times, before it hands the database back.

const openDb = (storeName, version = undefined, tries = 4) => new Promise((resolve, reject) => {
  const request = version ? indexedDB.open(DB_NAME, version) : indexedDB.open(DB_NAME)
  ensureStore(request, storeName)
  request.onerror = () => reject(request.error)
  request.onsuccess = () => {
    const db = request.result
    if (db.objectStoreNames.contains(storeName) || tries <= 0) return resolve(db)

    const next = db.version + 1
    db.close()
    openDb(storeName, next, tries - 1).then(resolve, reject)
  }
})

const transact = (db, storeName, mode, callback) => new Promise((resolve, reject) => {
  const tx = db.transaction(storeName, mode)
  const store = tx.objectStore(storeName)
  const request = callback(store)
  if (!request) {
    tx.oncomplete = () => resolve()
    tx.onerror = () => reject(tx.error)
    return
  }
  request.onsuccess = () => resolve(request.result)
  request.onerror = () => reject(request.error)
})

const withStore = async (storeName, callback) => {
  const db = await openDb(storeName)
  try {
    return await callback(db)
  } finally {
    db.close()
  }
}

export const get = (key, storeName = "keyval") => withStore(storeName, db => transact(db, storeName, "readonly", store => store.get(key)))
export const set = (key, value, storeName = "keyval") => withStore(storeName, db => transact(db, storeName, "readwrite", store => store.put(value, key)))
export const del = (key, storeName = "keyval") => withStore(storeName, db => transact(db, storeName, "readwrite", store => store.delete(key)))
export const clear = (storeName = "keyval") => withStore(storeName, db => transact(db, storeName, "readwrite", store => store.clear()))
export const keys = (storeName = "keyval") => withStore(storeName, db => transact(db, storeName, "readonly", store => store.getAllKeys()))
