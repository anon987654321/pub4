const CACHE_VERSION_MATCH = self.location.search.match(/[?&]v=([^&]+)/);
const CACHE_VERSION = CACHE_VERSION_MATCH ? CACHE_VERSION_MATCH[1] : 'v1';
const CACHE_NAME = `brgen-${CACHE_VERSION}-assets`;
const OFFLINE_URL = '/offline.html';
const STATIC_ASSETS = [
  '/offline.html',
  '/face.css',
  '/face.js',
  '/face.part1.txt',
  '/face.part2.txt',
  '/face.part3.txt',
  '/face.part4.txt',
  '/face.part5.txt',
  '/chat.js',
  '/three.face.module.js',
  '/manifest.json',
  '/icon.png'
];

self.addEventListener('install', e => {
  e.waitUntil(
    caches.open(CACHE_NAME)
      .then(cache => cache.addAll(STATIC_ASSETS))
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
  const url = new URL(e.request.url);
  if (e.request.mode === 'navigate') {
    e.respondWith(
      fetch(e.request)
        .catch(() => caches.match(OFFLINE_URL))
    );
    return;
  }
  if (url.pathname.startsWith('/assets/')) {
    e.respondWith(
      fetch(e.request).catch(() => caches.match(e.request))
    );
    return;
  }
  e.respondWith(
    fetch(e.request)
      .then(resp => {
        const clone = resp.clone();
        caches.open(CACHE_NAME).then(c => c.put(e.request, clone));
        return resp;
      })
      .catch(() => caches.match(e.request).then(cached => cached || caches.match(OFFLINE_URL)))
  );
});
