#!/usr/bin/env zsh
set -euo pipefail

# Rails 8 PWA Setup - Updated 2025
# Full Progressive Web App with offline support, push notifications

setup_pwa_manifest() {
  local app_name="${1:-RailsApp}"
  local theme_color="${2:-#1a73e8}"
  local background_color="${3:-#ffffff}"

  log "Generating PWA manifest for $app_name"
  mkdir -p public
  
  cat <<EOF > public/manifest.json
{
  "name": "${app_name}",
  "short_name": "${app_name}",
  "description": "${app_name} - Progressive Web Application",
  "start_url": "/",
  "display": "standalone",
  "orientation": "portrait-primary",
  "theme_color": "${theme_color}",
  "background_color": "${background_color}",
  "scope": "/",
  "icons": [
    {
      "src": "/icon-192.png",
      "sizes": "192x192",
      "type": "image/png",
      "purpose": "any maskable"
    },
    {
      "src": "/icon-512.png",
      "sizes": "512x512",
      "type": "image/png",
      "purpose": "any maskable"
    }
  ],
  "categories": ["social", "productivity"],
  "share_target": {
    "action": "/share",
    "method": "POST",
    "enctype": "multipart/form-data",
    "params": {
      "title": "title",
      "text": "text",
      "url": "url",
      "files": [
        {
          "name": "image",
          "accept": ["image/*"]
        }
      ]
    }
  },
  "shortcuts": [
    {
      "name": "New Post",
      "url": "/posts/new",
      "icons": [{ "src": "/icon-96.png", "sizes": "96x96" }]
    }
  ]
}
EOF
  log "PWA manifest generated at public/manifest.json"
}
setup_service_worker() {
  log "Generating Rails 8 service worker"
  mkdir -p public
  
  cat <<'EOF' > public/service-worker.js
// Service Worker for Rails 8 PWA
// Workbox-free, vanilla implementation

const CACHE_VERSION = 'v1'
const CACHE_NAME = `rails-pwa-${CACHE_VERSION}`

const STATIC_ASSETS = [
  '/',
  '/offline'
]

const CACHE_FIRST = [
  /\.css$/,
  /\.js$/,
  /\.woff2$/,
  /\.png$/,
  /\.jpg$/,
  /\.webp$/,
  /\.svg$/
]

const NETWORK_FIRST = [
  /\/api\//,
  /\/__turbo/,
  /\/cable$/
]

self.addEventListener('install', event => {
  event.waitUntil(
    caches.open(CACHE_NAME)
      .then(cache => cache.addAll(STATIC_ASSETS))
      .then(() => self.skipWaiting())
  )
})

self.addEventListener('activate', event => {
  event.waitUntil(
    caches.keys()
      .then(keys => Promise.all(
        keys.map(key => key !== CACHE_NAME && caches.delete(key))
      ))
      .then(() => self.clients.claim())
  )
})

self.addEventListener('fetch', event => {
  const { request } = event
  const url = new URL(request.url)

  if (url.origin !== location.origin) return

  if (NETWORK_FIRST.some(p => p.test(url.pathname))) {
    event.respondWith(networkFirst(request))
  } else if (CACHE_FIRST.some(p => p.test(url.pathname))) {
    event.respondWith(cacheFirst(request))
  } else {
    event.respondWith(networkFirst(request))
  }
})

async function cacheFirst(request) {
  const cached = await caches.match(request)
  if (cached) return cached

  try {
    const response = await fetch(request)
    if (response.ok) {
      const cache = await caches.open(CACHE_NAME)
      cache.put(request, response.clone())
    }
    return response
  } catch {
    return caches.match('/offline')
  }
}

async function networkFirst(request) {
  try {
    const response = await fetch(request)
    if (response.ok) {
      const cache = await caches.open(CACHE_NAME)
      cache.put(request, response.clone())
    }
    return response
  } catch {
    return await caches.match(request) || caches.match('/offline')
  }
}

self.addEventListener('push', event => {
  const data = event.data?.json() || {}
  event.waitUntil(
    self.registration.showNotification(data.title || 'Notification', {
      body: data.body,
      icon: '/icon-192.png',
      badge: '/icon-72.png',
      data: { url: data.url || '/' }
    })
  )
})

self.addEventListener('notificationclick', event => {
  event.notification.close()
  event.waitUntil(
    clients.matchAll({ type: 'window' }).then(list => {
      for (const client of list) {
        if (client.url === event.notification.data.url) {
          return client.focus()
        }
      }
      return clients.openWindow(event.notification.data.url)
    })
  )
})
EOF
  log "Service worker generated at public/service-worker.js"
}
setup_offline_page() {
  log "Generating offline page"
  mkdir -p app/views/errors
  
  cat <<'EOF' > app/views/errors/offline.html.erb
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Offline</title>
  <%= csrf_meta_tags %>
  <%= csp_meta_tag %>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: system-ui, -apple-system, sans-serif;
      background: #f5f5f5;
      color: #202124;
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
      font-weight: 600;
    }
    p {
      font-size: 1rem;
      line-height: 1.6;
      margin-bottom: 2rem;
      opacity: 0.7;
    }
    button {
      background: #1a73e8;
      color: white;
      border: none;
      padding: 0.75rem 1.5rem;
      font-size: 1rem;
      border-radius: 0.5rem;
      cursor: pointer;
      font-weight: 500;
    }
    button:hover {
      background: #1557b0;
    }
  </style>
</head>
<body>
  <main>
    <h1>You're Offline</h1>
    <p>No internet connection. Your data is safe and will sync when you're back online.</p>
    <button onclick="window.location.reload()">Try Again</button>
  </main>
</body>
</html>
EOF

  cat <<'EOF' > config/routes.rb
Rails.application.routes.draw do
  get '/offline', to: 'errors#offline'
end
EOF
  
  log "Offline page generated"
}

setup_pwa_controller() {
  log "Generating PWA controller"
  mkdir -p app/controllers
  
  cat <<'EOF' > app/controllers/errors_controller.rb
class ErrorsController < ApplicationController
  def offline
    render layout: false
  end
end
EOF
  log "PWA controller generated"
}

setup_pwa_helpers() {
  log "Generating PWA helpers"
  mkdir -p app/helpers
  
  cat <<'EOF' > app/helpers/pwa_helper.rb
module PwaHelper
  def pwa_meta_tags
    safe_join([
      tag.meta(name: "mobile-web-app-capable", content: "yes"),
      tag.meta(name: "apple-mobile-web-app-capable", content: "yes"),
      tag.meta(name: "apple-mobile-web-app-status-bar-style", content: "black-translucent"),
      tag.meta(name: "apple-mobile-web-app-title", content: app_name),
      tag.link(rel: "manifest", href: "/manifest.json"),
      tag.link(rel: "apple-touch-icon", href: "/icon-192.png")
    ], "\n    ")
  end

  def register_service_worker
    javascript_tag <<~JS, type: "module"
      if ('serviceWorker' in navigator) {
        navigator.serviceWorker.register('/service-worker.js')
          .then(reg => console.log('SW registered:', reg.scope))
          .catch(err => console.error('SW registration failed:', err))
      }
    JS
  end

  private

  def app_name
    Rails.application.class.module_parent_name
  end
end
EOF
  log "PWA helpers generated"
}
setup_full_pwa() {
  local app_name="${1:-RailsApp}"
  log "Setting up Rails 8 PWA for $app_name"
  
  setup_pwa_manifest "$app_name"
  setup_service_worker
  setup_offline_page
  setup_pwa_controller
  setup_pwa_helpers
  
  log "✓ Rails 8 PWA complete"
  log "Add to app/views/layouts/application.html.erb:"
  log "  <%= pwa_meta_tags %>"
  log "  <%= register_service_worker %>"
}
