# frozen_string_literal: true

module Shared
  # Serving the three files a PWA installs from: the manifest, the service
  # worker, and the offline page the worker shows when there is no connection.
  #
  # This lives in the engine because the hardening below is not app-specific and
  # was only ever applied to one app. amber and bsdports answered 422
  # (ActionController::InvalidCrossOriginRequest) for /service-worker.js: a
  # `render js:` response goes through verify_same_origin_request, which refuses
  # unless forgery protection is skipped, so neither app's service worker could
  # register and neither PWA installed. brgen carried the fix and the comment
  # explaining it; the other two carried the original.
  #
  # RAILS/test/app_duplication_test.rb did not catch that, and could not: it
  # compares files byte-for-byte, so three copies of a controller stay invisible
  # to it for exactly as long as one of them is being fixed. Divergence is what
  # it is blind to, and divergence is the failure.
  #
  # What is left in each app is the host constant Rails resolves by bare name,
  # plus the two strings the offline page needs — under the duplication budget
  # and genuinely different per app.
  module PwaServing
    extend ActiveSupport::Concern

    CACHE_VERSION_PLACEHOLDER = "__CACHE_VERSION__"

    included do
      # A service worker and a manifest are fetched by the browser without any
      # session, and must install without CSRF noise.
      skip_forgery_protection
    end

    def manifest
      response.headers["Cache-Control"] = "public, max-age=300"
      render template: "pwa/manifest", formats: :json, content_type: "application/manifest+json"
    end

    def service_worker
      # Service-Worker-Allowed widens the worker's scope to the whole origin;
      # without it a worker served from anywhere but / controls only its own
      # directory.
      response.headers["Service-Worker-Allowed"] = "/"
      response.headers["Cache-Control"] = "public, max-age=0, must-revalidate"
      render js: service_worker_source, content_type: "application/javascript", layout: false
    rescue StandardError => e
      ::Rails.logger.error("[pwa] service_worker render failed: #{e.class}: #{e.message}")
      # A worker that fails to render must still be a valid worker. Returning an
      # error page here leaves the previously installed worker in place serving
      # a stale cache, with no route back.
      render plain: "/* service worker unavailable */\nself.addEventListener('install', () => self.skipWaiting());\n",
             content_type: "application/javascript",
             status: :ok
    end

    def offline
      # `render partial:` with `layout:` asks for a PARTIAL layout — Rails looks
      # for layouts/_application, which does not exist in any of these apps, so
      # /offline answered 500. It is the page the service worker shows when the
      # visitor has no connection, which is exactly when a 500 is least useful.
      body = render_to_string(partial: "shared/offline_page",
                              locals: { app_name: pwa_app_name, storage_key: pwa_storage_key })
      render html: body.html_safe, layout: "application"
    end

    private

    # ApplicationController's allow_browser before_action calls this instance
    # method. Overridden so worker install never gets 406/422 from the
    # modern-browser gate — the fetch that installs a worker does not carry the
    # user agent that gate reads.
    def allow_browser(*); end

    def service_worker_source
      render_to_string(template: "pwa/service-worker", layout: false)
        .gsub(CACHE_VERSION_PLACEHOLDER, ENV.fetch("CACHE_VERSION", "v2"))
    end
  end
end
