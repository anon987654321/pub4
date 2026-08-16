const CACHE_VERSION_MATCH = self.location.search.match(/[?&]v=([^&]+)/);
const CACHE_VERSION = CACHE_VERSION_MATCH ? CACHE_VERSION_MATCH[1] : 'v2';
const CACHE_NAME = `brgen-${CACHE_VERSION}-assets`;
const OFFLINE_URL = '/offline.html';
// Precache only shell assets that are stable across deploys. Digested /assets/*
// URLs are cached opportunistically on successful fetch (network-first below).
const STATIC_ASSETS = [
  OFFLINE_URL,
  '/manifest.json'
];
const DYNAMIC_PREFIXES = ['/chat/', '/canvas/', '/events/', '/runtime/', '/bridge/', '/dashboard/'];

self.addEventListener('install', e => {
  e.waitUntil(
    caches.open(CACHE_NAME)
      .then(cache => Promise.allSettled(STATIC_ASSETS.map(url => cache.add(url))))
      .then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', e => {
  e.waitUntil(
    caches.keys()
      .then(keys => Promise.all(
        keys.filter(k => k !== CACHE_NAME).map(k => caches.delete(k))
      ))
      .then(() => self.clients.claim())
      .then(() => self.clients.matchAll({ type: 'window' }).then(clients => {
        clients.forEach(client => client.postMessage({ type: 'sw:updated', version: CACHE_VERSION }));
      }))
  );
});

self.addEventListener('fetch', e => {
  if (e.request.method !== 'GET') return;
  const url = new URL(e.request.url);
  if (url.origin !== self.location.origin) return;

  if (e.request.mode === 'navigate') {
    e.respondWith(
      fetch(e.request)
        .catch(() => caches.match('/') || caches.match(OFFLINE_URL))
    );
    return;
  }

  // Never cache digested /assets/* — stale hashes wedge primer/face boot after deploy.
  if (url.pathname.startsWith('/assets/')) {
    e.respondWith(fetch(e.request));
    return;
  }

  // Dynamic API/SSE endpoints: passthrough only, never cache. chat/message,
  // chat/tts/stream, and events/stream are long-lived streams that never
  // finish in a way Cache Storage can store — cloning and caching them throws
  // "Cache.put() encountered a network error" the moment the stream is
  // aborted (new message sent, reconnect, navigation). Status polls are just
  // pointless to cache.
  if (DYNAMIC_PREFIXES.some(p => url.pathname.startsWith(p))) {
    e.respondWith(fetch(e.request).catch(() => Response.error()));
    return;
  }

  e.respondWith(
    fetch(e.request)
      .then(resp => {
        if (resp.ok) {
          const clone = resp.clone();
          caches.open(CACHE_NAME).then(c => c.put(e.request, clone));
        }
        return resp;
      })
      .catch(() => caches.match(e.request).then(cached => cached || caches.match(OFFLINE_URL)))
  );
});

// Offline-first memory bridge. Clients can postMessage({ type: 'offline:drain' })
// after coming online. The actual drain lives in offline_memory.js (page
// context); the SW only forwards so a future Background Sync registration has
// a single entry point.
self.addEventListener('message', (event) => {
  const data = event.data || {};
  if (data.type === 'offline:drain' && event.source) {
    event.source.postMessage({ type: 'offline:drain-ack', ts: Date.now() });
  }
});

