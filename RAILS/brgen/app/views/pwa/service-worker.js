// brgen service worker — hand-rolled, deliberately minimal.
//
// The previous build was a Workbox bundle whose precache manifest froze ~89
// fingerprinted asset URLs at build time. Every deploy re-digests those assets,
// so the manifest drifted and `install` failed with bad-precaching-response
// (e.g. assets/stimulus_components-64519f38.js 404), which broke the PWA on
// playlist.brgen.no. Precaching content-addressed bundles is the wrong tool:
// their whole point is that the URL changes with the content. So we precache
// only the stable offline page and runtime-cache everything else.
//
// __CACHE_VERSION__ is substituted per deploy by Rails::PwaController, so each
// deploy gets fresh cache buckets and the old ones are swept on activate.

const VERSION = "__CACHE_VERSION__";
const PRECACHE = `brgen-precache-${VERSION}`;
const RUNTIME = `brgen-runtime-${VERSION}`;

// Stable, non-fingerprinted resources only. The offline page is the one thing a
// disconnected navigation needs. `add` is best-effort per URL (allSettled), so a
// missing optional URL can never fail install — that was the entire prior bug.
const PRECACHE_URLS = ["/offline"];

self.addEventListener("install", (event) => {
  event.waitUntil(
    caches
      .open(PRECACHE)
      .then((cache) => Promise.allSettled(PRECACHE_URLS.map((url) => cache.add(url))))
      .then(() => self.skipWaiting())
  );
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((keys) =>
        Promise.all(
          keys.filter((key) => key !== PRECACHE && key !== RUNTIME).map((key) => caches.delete(key))
        )
      )
      .then(() => self.clients.claim())
  );
});

self.addEventListener("fetch", (event) => {
  const request = event.request;
  if (request.method !== "GET") return;

  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return;

  // Fingerprinted assets: stale-while-revalidate. Safe to serve stale because the
  // URL is content-addressed — a changed asset is a different URL, never a 404.
  if (url.pathname.startsWith("/assets/")) {
    event.respondWith(
      caches.open(RUNTIME).then((cache) =>
        cache.match(request).then((cached) => {
          const fresh = fetch(request)
            .then((response) => {
              if (response && response.status === 200) cache.put(request, response.clone());
              return response;
            })
            .catch(() => cached);
          return cached || fresh;
        })
      )
    );
    return;
  }

  // Navigations: network-first, fall back to the cached offline page.
  if (request.mode === "navigate") {
    event.respondWith(fetch(request).catch(() => caches.match("/offline")));
  }
});

// Web Push. The server (WebPushJob) sends a JSON payload; show it, and focus or
// open the target on click. Retention's biggest lever — everything upstream
// (VAPID, subscriptions, the webpush gem) already existed; this is the last mile.
self.addEventListener("push", (event) => {
  let data = {};
  try {
    data = event.data ? event.data.json() : {};
  } catch (e) {
    data = { title: "brgen", body: event.data ? event.data.text() : "" };
  }
  const title = data.title || "brgen";
  const options = {
    body: data.body || "",
    icon: "/icon-192.png",
    badge: "/icon-mono-192.png",
    tag: data.tag,
    data: { url: data.url || "/" },
  };
  event.waitUntil(self.registration.showNotification(title, options));
});

self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  const target = (event.notification.data && event.notification.data.url) || "/";
  event.waitUntil(
    clients.matchAll({ type: "window", includeUncontrolled: true }).then((wins) => {
      for (const w of wins) {
        if (w.url.includes(target) && "focus" in w) return w.focus();
      }
      return clients.openWindow(target);
    })
  );
});
