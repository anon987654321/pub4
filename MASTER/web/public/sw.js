const CACHE_VERSION_MATCH = self.location.search.match(/[?&]v=([^&]+)/);
const CACHE_VERSION = CACHE_VERSION_MATCH ? CACHE_VERSION_MATCH[1] : 'v1';
const CACHE_NAME = `brgen-${CACHE_VERSION}-assets`;
const OFFLINE_URL = '/offline.html';
const STATIC_ASSETS = [
  '/offline.html',
  '/face.css',
  '/face.js',
  '/chat.js',
  '/three.face.module.js',
  '/manifest.json',
  '/icon.png'
];

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
  );
});

self.addEventListener('fetch', e => {
  if (e.request.method !== 'GET') return;
  if (e.request.mode === 'navigate') return;

  const url = new URL(e.request.url);
  if (url.origin !== self.location.origin) return;

  e.respondWith(
    fetch(e.request)
      .then(resp => {
        if (resp.ok) {
          const clone = resp.clone();
          caches.open(CACHE_NAME).then(c => c.put(e.request, clone));
        }
        return resp;
      })
      .catch(() => caches.match(e.request))
  );
});