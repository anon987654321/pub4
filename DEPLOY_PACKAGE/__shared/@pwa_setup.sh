#!/usr/bin/env zsh
set -euo pipefail

# PWA setup script for Rails 8 applications
# Generates manifest.json and service-worker.js per master.json requirements

setup_pwa_manifest() {
  local app_name="${1:-RailsApp}"

  local theme_color="${2:-#000000}"
  local background_color="${3:-#ffffff}"

  log "Generating PWA manifest for $app_name"
  mkdir -p app/assets/config

  mkdir -p app/assets/images/icons

  cat <<EOF > app/assets/config/manifest.json

{
  "name": "${app_name}",
  "short_name": "${app_name}",

  "description": "${app_name} Progressive Web Application",
  "start_url": "/",

  "display": "standalone",

  "orientation": "portrait-primary",

  "theme_color": "${theme_color}",

  "background_color": "${background_color}",

  "scope": "/",

  "icons": [

    {

      "src": "/assets/icons/icon-72x72.png",

      "sizes": "72x72",

      "type": "image/png",

      "purpose": "any"

    },

    {

      "src": "/assets/icons/icon-96x96.png",

      "sizes": "96x96",

      "type": "image/png",

      "purpose": "any"

    },

    {

      "src": "/assets/icons/icon-128x128.png",

      "sizes": "128x128",

      "type": "image/png",

      "purpose": "any"

    },

    {

      "src": "/assets/icons/icon-144x144.png",

      "sizes": "144x144",

      "type": "image/png",

      "purpose": "any"

    },

    {

      "src": "/assets/icons/icon-152x152.png",

      "sizes": "152x152",

      "type": "image/png",

      "purpose": "any"

    },

    {

      "src": "/assets/icons/icon-192x192.png",

      "sizes": "192x192",

      "type": "image/png",

      "purpose": "any maskable"

    },

    {

      "src": "/assets/icons/icon-384x384.png",

      "sizes": "384x384",

      "type": "image/png",

      "purpose": "any"

    },

    {

      "src": "/assets/icons/icon-512x512.png",

      "sizes": "512x512",

      "type": "image/png",

      "purpose": "any maskable"

    }

  ],

  "categories": ["social", "productivity"],

  "screenshots": [],

  "share_target": {

    "action": "/share",

    "method": "POST",

    "enctype": "multipart/form-data",

    "params": {

      "title": "title",

      "text": "text",

      "url": "url"

    }

  }

}

EOF

  log "PWA manifest generated"

}

setup_service_worker() {

  local app_name="${1:-RailsApp}"

  log "Generating service worker for $app_name"
  mkdir -p app/javascript

  cat <<'EOF' > app/javascript/service-worker.js
// Service Worker for Rails 8 PWA

// Cache-first strategy per master.json line 451
const CACHE_VERSION = 'v1'
const CACHE_NAME = `${self.registration.scope}-${CACHE_VERSION}`
const STATIC_ASSETS = [

  '/',

  '/assets/application.css',
  '/assets/application.js',

  '/offline.html'
]

const CACHE_FIRST_ROUTES = [

  /\.css$/,

  /\.js$/,

  /\.woff2$/,

  /\.png$/,
  /\.jpg$/,

  /\.svg$/

]

const NETWORK_FIRST_ROUTES = [

  /\/api\//,

  /\/turbo-stream/

]

self.addEventListener('install', event => {
  event.waitUntil(

    caches.open(CACHE_NAME).then(cache => {

      return cache.addAll(STATIC_ASSETS)

    }).then(() => {
      return self.skipWaiting()

    })

  )

})

self.addEventListener('activate', event => {

  event.waitUntil(

    caches.keys().then(cacheNames => {

      return Promise.all(

        cacheNames.map(cacheName => {
          if (cacheName !== CACHE_NAME) {

            return caches.delete(cacheName)

          }

        })

      )

    }).then(() => {

      return self.clients.claim()

    })

  )

})

self.addEventListener('fetch', event => {

  const { request } = event

  const url = new URL(request.url)

  // Skip cross-origin requests

  if (url.origin !== location.origin) {
    return

  }

  // Network-first for API and Turbo Stream requests
  if (NETWORK_FIRST_ROUTES.some(pattern => pattern.test(url.pathname))) {

    event.respondWith(networkFirst(request))

    return

  }
  // Cache-first for static assets

  if (CACHE_FIRST_ROUTES.some(pattern => pattern.test(url.pathname))) {

    event.respondWith(cacheFirst(request))

    return

  }
  // Default: Network-first with cache fallback

  event.respondWith(networkFirst(request))

})

async function cacheFirst(request) {

  const cachedResponse = await caches.match(request)
  if (cachedResponse) {

    return cachedResponse

  }
  try {

    const networkResponse = await fetch(request)

    if (networkResponse.ok) {

      const cache = await caches.open(CACHE_NAME)

      cache.put(request, networkResponse.clone())
    }

    return networkResponse

  } catch (error) {

    return caches.match('/offline.html')

  }

}

async function networkFirst(request) {

  try {

    const networkResponse = await fetch(request)

    if (networkResponse.ok) {

      const cache = await caches.open(CACHE_NAME)
      cache.put(request, networkResponse.clone())

    }

    return networkResponse

  } catch (error) {

    const cachedResponse = await caches.match(request)

    if (cachedResponse) {

      return cachedResponse

    }

    return caches.match('/offline.html')

  }

}

// Background sync for offline form submissions

self.addEventListener('sync', event => {

  if (event.tag === 'sync-forms') {

    event.waitUntil(syncForms())

  }
})

async function syncForms() {

  const cache = await caches.open(`${CACHE_NAME}-pending`)

  const requests = await cache.keys()

  await Promise.all(

    requests.map(async request => {
      try {

        await fetch(request.clone())

        await cache.delete(request)
      } catch (error) {

        console.error('Sync failed for:', request.url)

      }

    })

  )

}

// Push notifications

self.addEventListener('push', event => {

  const data = event.data ? event.data.json() : {}

  const options = {

    body: data.body || 'New notification',
    icon: '/assets/icons/icon-192x192.png',

    badge: '/assets/icons/icon-72x72.png',

    vibrate: [200, 100, 200],
    data: {

      url: data.url || '/'

    },

    actions: data.actions || []

  }

  event.waitUntil(

    self.registration.showNotification(data.title || 'Notification', options)

  )

})

self.addEventListener('notificationclick', event => {
  event.notification.close()

  const urlToOpen = event.notification.data.url

  event.waitUntil(

    clients.matchAll({ type: 'window', includeUncontrolled: true }).then(clientList => {
      for (const client of clientList) {

        if (client.url === urlToOpen && 'focus' in client) {
          return client.focus()
        }

      }

      if (clients.openWindow) {

        return clients.openWindow(urlToOpen)

      }

    })

  )

})

EOF

  log "Service worker generated"

}

setup_offline_page() {

  log "Generating offline fallback page"

  mkdir -p public
  cat <<'EOF' > public/offline.html

<!DOCTYPE html>
<html lang="en">

<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">

  <title>Offline</title>

  <style>

    :root {

      --color-bg: #ffffff;

      --color-text: #202124;

      --color-primary: #1a73e8;

    }

    @media (prefers-color-scheme: dark) {

      :root {

        --color-bg: #202124;

        --color-text: #e8eaed;

        --color-primary: #8ab4f8;
      }

    }

    * {

      box-sizing: border-box;

      margin: 0;

      padding: 0;

    }
    body {

      font-family: system-ui, -apple-system, sans-serif;

      background-color: var(--color-bg);

      color: var(--color-text);

      display: flex;
      align-items: center;

      justify-content: center;

      min-height: 100vh;

      padding: 1rem;

    }

    main {

      text-align: center;

      max-width: 400px;

    }

    h1 {
      font-size: 2rem;

      margin-bottom: 1rem;

    }

    p {
      font-size: 1rem;

      line-height: 1.5;

      margin-bottom: 2rem;

      color: var(--color-text);
      opacity: 0.8;

    }

    button {

      background-color: var(--color-primary);

      color: white;

      border: none;

      padding: 0.75rem 1.5rem;
      font-size: 1rem;

      border-radius: 0.375rem;

      cursor: pointer;

    }

    button:hover {

      opacity: 0.9;

    }

  </style>

</head>
<body>

  <main role="main">

    <h1>You're Offline</h1>

    <p>It looks like you've lost your internet connection. Don't worry, your data is safe and will sync when you're back online.</p>

    <button onclick="window.location.reload()">Try Again</button>

  </main>

</body>

</html>

EOF

  log "Offline page generated"

}

setup_pwa_helpers() {

  log "Generating PWA helper for application layout"

  mkdir -p app/helpers
  cat <<'EOF' > app/helpers/pwa_helper.rb

module PwaHelper
  def pwa_meta_tags

    safe_join([
      tag.meta(name: "mobile-web-app-capable", content: "yes"),
      tag.meta(name: "apple-mobile-web-app-capable", content: "yes"),

      tag.meta(name: "apple-mobile-web-app-status-bar-style", content: "black-translucent"),

      tag.meta(name: "apple-mobile-web-app-title", content: Rails.application.class.module_parent_name),

      tag.link(rel: "manifest", href: asset_path("manifest.json")),

      tag.link(rel: "apple-touch-icon", href: asset_path("icons/icon-192x192.png"))

    ], "\n")

  end

  def register_service_worker

    javascript_tag <<~JS

      if ('serviceWorker' in navigator) {

        navigator.serviceWorker.register('/service-worker.js').then(registration => {

          console.log('Service Worker registered:', registration.scope)
        }).catch(error => {

          console.error('Service Worker registration failed:', error)

        })

      }

    JS

  end

  def request_notification_permission

    javascript_tag <<~JS

      if ('Notification' in window && 'serviceWorker' in navigator) {

        Notification.requestPermission().then(permission => {

          console.log('Notification permission:', permission)
        })

      }

    JS

  end

end

EOF

  log "PWA helper generated"

}

setup_full_pwa() {

  local app_name="${1:-RailsApp}"

  log "Setting up full PWA for $app_name"
  setup_pwa_manifest "$app_name"

  setup_service_worker "$app_name"
  setup_offline_page

  setup_pwa_helpers
  log "Full PWA setup complete for $app_name"
  log "Add <%= pwa_meta_tags %> and <%= register_service_worker %> to application.html.erb"

}

