# frozen_string_literal: true

module Rails
  class PwaController < ApplicationController
    CACHE_VERSION_PLACEHOLDER = "__CACHE_VERSION__"

    # Service workers / manifests must install without CSRF noise.
    skip_forgery_protection

    def manifest
      response.headers["Cache-Control"] = "public, max-age=300"
      render template: "pwa/manifest", formats: :json, content_type: "application/manifest+json"
    end

    def service_worker
      response.headers["Service-Worker-Allowed"] = "/"
      response.headers["Cache-Control"] = "public, max-age=0, must-revalidate"
      render js: service_worker_source, content_type: "application/javascript", layout: false
    rescue StandardError => e
      Rails.logger.error("[pwa] service_worker render failed: #{e.class}: #{e.message}")
      render plain: "/* service worker unavailable */\nself.addEventListener('install', () => self.skipWaiting());\n",
             content_type: "application/javascript",
             status: :ok
    end

    def offline
# `render partial:` with `layout:` asks for a PARTIAL layout — Rails looks
# for layouts/_application, which does not exist in any of these apps, so
# /offline answered 500. It is the page the service worker shows when the
# visitor has no connection, which is exactly when a 500 is least useful.
# Rendering the partial to a string and handing that to `render html:`
# takes the real application layout.
body = render_to_string(partial: "shared/offline_page",
                        locals: { app_name: "brgen", storage_key: "brgen" })
render html: body.html_safe, layout: "application"
    end

    private

    # ApplicationController's allow_browser before_action calls this instance method.
    # Override so SW install never gets 406/422 from the modern-browser gate.
    def allow_browser(*)
    end

    def service_worker_source
      render_to_string(template: "pwa/service-worker", layout: false)
        .gsub(CACHE_VERSION_PLACEHOLDER, ENV.fetch("CACHE_VERSION", "v2"))
    end
  end
end
