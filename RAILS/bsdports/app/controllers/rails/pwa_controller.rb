# frozen_string_literal: true

module Rails
  class PwaController < ApplicationController
    CACHE_VERSION_PLACEHOLDER = "__CACHE_VERSION__"

    def manifest
      http_cache_forever(public: false) do
        render template: "pwa/manifest", formats: :json
      end
    end

    def service_worker
      http_cache_forever(public: false) do
        render js: service_worker_source, content_type: "application/javascript"
      end
    end

    def offline
# `render partial:` with `layout:` asks for a PARTIAL layout — Rails looks
# for layouts/_application, which does not exist in any of these apps, so
# /offline answered 500. It is the page the service worker shows when the
# visitor has no connection, which is exactly when a 500 is least useful.
# Rendering the partial to a string and handing that to `render html:`
# takes the real application layout.
body = render_to_string(partial: "shared/offline_page",
                        locals: { app_name: "BSDports", storage_key: "bsdports" })
render html: body.html_safe, layout: "application"
    end

    private

    def service_worker_source
      render_to_string(template: "pwa/service-worker", layout: false)
        .gsub(CACHE_VERSION_PLACEHOLDER, ENV.fetch("CACHE_VERSION", "v2"))
    end
  end
end
