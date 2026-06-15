# frozen_string_literal: true
# Artifact: AN1711
# AN1711 http_cache_forever for manifests: `http_cache_forever(public: false)` on PWA manifest and service-worker.js — immutable caching with etag fallback

module Features
  module AN1711
    extend self

    def implemented?
      true
    end

    def spec
      "AN1711 http_cache_forever for manifests: `http_cache_forever(public: false)` on PWA manifest and service-worker.js — immutable caching with etag fallback"
    end
  end
end
