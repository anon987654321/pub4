/**
 * offline_memory.js — local-first transcript + event queue for MASTER face.
 *
 * Scaffold for the offline_first_memory opportunity cluster.
 *
 * Goals:
 * - Keep recent assistant state on-device so the face remains useful when
 *   the network or provider is down.
 * - Queue user turns and system events for later sync.
 * - Never claim durability the browser does not actually provide.
 *
 * Schema (IndexedDB "master_offline", version 1):
 *   transcripts  { id, sessionId, role, text, ts, synced }
 *   event_queue  { id, type, payload, ts, attempts, lastError }
 *   attention    { key, value, ts }   // lightweight attention breadcrumbs
 *
 * This module is intentionally side-effect free on import. Call
 * OfflineMemory.open() once after the primer tap (or from SW message).
 *
 * Status: scaffold only — no automatic wiring into chat.js yet.
 * Next: wire enqueueTurn into chat_actions after successful local
 * render; drain queue on 'online' + SW 'sync' if available.
 */
(function (global) {
  "use strict";

  const DB_NAME = "master_offline";
  const DB_VERSION = 1;

  function openDb() {
    return new Promise((resolve, reject) => {
      if (!global.indexedDB) {
        reject(new Error("indexedDB unavailable"));
        return;
      }
      const req = global.indexedDB.open(DB_NAME, DB_VERSION);
      req.onupgradeneeded = (ev) => {
        const db = ev.target.result;
        if (!db.objectStoreNames.contains("transcripts")) {
          const t = db.createObjectStore("transcripts", { keyPath: "id", autoIncrement: true });
          t.createIndex("by_session", "sessionId", { unique: false });
          t.createIndex("by_synced", "synced", { unique: false });
        }
        if (!db.objectStoreNames.contains("event_queue")) {
          const q = db.createObjectStore("event_queue", { keyPath: "id", autoIncrement: true });
          q.createIndex("by_type", "type", { unique: false });
        }
        if (!db.objectStoreNames.contains("attention")) {
          db.createObjectStore("attention", { keyPath: "key" });
        }
      };
      req.onsuccess = () => resolve(req.result);
      req.onerror = () => reject(req.error || new Error("idb open failed"));
    });
  }

  function txDone(tx) {
    return new Promise((resolve, reject) => {
      tx.oncomplete = () => resolve();
      tx.onerror = () => reject(tx.error);
      tx.onabort = () => reject(tx.error || new Error("tx aborted"));
    });
  }

  const OfflineMemory = {
    _db: null,

    async open() {
      if (this._db) return this._db;
      this._db = await openDb();
      return this._db;
    },

    async enqueueTurn({ sessionId, role, text, ts }) {
      const db = await this.open();
      const tx = db.transaction("transcripts", "readwrite");
      tx.objectStore("transcripts").add({
        sessionId: sessionId || "default",
        role: role || "user",
        text: String(text || "").slice(0, 32_000),
        ts: ts || Date.now(),
        synced: 0,
      });
      await txDone(tx);
    },

    async enqueueEvent({ type, payload }) {
      const db = await this.open();
      const tx = db.transaction("event_queue", "readwrite");
      tx.objectStore("event_queue").add({
        type: String(type || "unknown"),
        payload: payload || {},
        ts: Date.now(),
        attempts: 0,
        lastError: null,
      });
      await txDone(tx);
    },

    async recentTranscript(sessionId, limit) {
      const db = await this.open();
      const tx = db.transaction("transcripts", "readonly");
      const store = tx.objectStore("transcripts");
      const index = store.index("by_session");
      const rows = [];
      return new Promise((resolve, reject) => {
        const req = index.openCursor(IDBKeyRange.only(sessionId || "default"), "prev");
        req.onsuccess = (ev) => {
          const cursor = ev.target.result;
          if (cursor && rows.length < (limit || 40)) {
            rows.push(cursor.value);
            cursor.continue();
          } else {
            resolve(rows.reverse());
          }
        };
        req.onerror = () => reject(req.error);
      });
    },

    async pendingEvents(limit) {
      const db = await this.open();
      const tx = db.transaction("event_queue", "readonly");
      const store = tx.objectStore("event_queue");
      const rows = [];
      return new Promise((resolve, reject) => {
        const req = store.openCursor();
        req.onsuccess = (ev) => {
          const cursor = ev.target.result;
          if (cursor && rows.length < (limit || 50)) {
            rows.push(cursor.value);
            cursor.continue();
          } else {
            resolve(rows);
          }
        };
        req.onerror = () => reject(req.error);
      });
    },

    async setAttention(key, value) {
      const db = await this.open();
      const tx = db.transaction("attention", "readwrite");
      tx.objectStore("attention").put({ key: String(key), value, ts: Date.now() });
      await txDone(tx);
    },

    /** Best-effort drain; caller supplies the network sender. */
    async drainEvents(sender) {
      const pending = await this.pendingEvents(20);
      const results = [];
      for (const ev of pending) {
        try {
          await sender(ev);
          const db = await this.open();
          const tx = db.transaction("event_queue", "readwrite");
          tx.objectStore("event_queue").delete(ev.id);
          await txDone(tx);
          results.push({ id: ev.id, ok: true });
        } catch (err) {
          results.push({ id: ev.id, ok: false, error: String(err && err.message || err) });
        }
      }
      return results;
    },
  };

  global.OfflineMemory = OfflineMemory;
})(typeof self !== "undefined" ? self : window);
