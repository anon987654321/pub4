# frozen_string_literal: true

# Shared PWA importmap pins — append to each app's config/importmap.rb
PWA_IMPORTMAP_PINS = <<~RUBY
  pin "idb-keyval", to: "https://esm.sh/idb-keyval@6.2.1"
  pin "pwa/offline_store", to: "pwa/offline_store.js"
  pin "pwa/bootstrap", to: "pwa/bootstrap.js"
RUBY