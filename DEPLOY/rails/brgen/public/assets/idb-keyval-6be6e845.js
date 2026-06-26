const DB_NAME = "brgen-idb-keyval"
const DB_VERSION = 1

const openDb = (storeName) => new Promise((resolve, reject) => {
  const request = indexedDB.open(DB_NAME, DB_VERSION)
  request.onupgradeneeded = () => {
    const db = request.result
    if (!db.objectStoreNames.contains(storeName)) db.createObjectStore(storeName)
  }
  request.onsuccess = () => resolve(request.result)
  request.onerror = () => reject(request.error)
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
